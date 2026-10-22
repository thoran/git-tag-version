# test/git-tag-version_test.rb

# 20261022
# 0.0.0

# Each test runs git-tag-version as a subprocess in a clone of a bare repository
# made for the purpose, standing in for origin, and asserts upon which tags the
# clone and origin end up with.  Tags are signed by test/fake-gpg.

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

BIN = File.expand_path('../bin/git-tag-version', __dir__)
FAKE_GPG = File.expand_path('fake-gpg', __dir__)

ENV['GIT_CONFIG_COUNT'] = '5'
ENV['GIT_CONFIG_KEY_0'] = 'commit.gpgsign'
ENV['GIT_CONFIG_VALUE_0'] = 'false'
ENV['GIT_CONFIG_KEY_1'] = 'tag.gpgsign'
ENV['GIT_CONFIG_VALUE_1'] = 'false'
ENV['GIT_CONFIG_KEY_2'] = 'gpg.program'
ENV['GIT_CONFIG_VALUE_2'] = FAKE_GPG
ENV['GIT_CONFIG_KEY_3'] = 'advice.detachedHead'
ENV['GIT_CONFIG_VALUE_3'] = 'false'
ENV['GIT_CONFIG_KEY_4'] = 'push.followTags'
ENV['GIT_CONFIG_VALUE_4'] = 'false'

def git(*arguments)
  system('git', *arguments, out: File::NULL, err: File::NULL) || raise("git #{arguments.join(' ')} failed")
end

def sha(ref)
  `git rev-parse --verify --quiet #{ref}^{commit}`.strip
end

def tag_object(tag)
  `git cat-file -p refs/tags/#{tag} 2>/dev/null`
end

def origin_tag_commit(tag)
  `git ls-remote origin refs/tags/#{tag}^{}`.split.first
end

def changelog(version)
  "# CHANGELOG\n\n## 20261022\n\n#{version}: The release.\n\n1. + something\n"
end

def program(name, version)
  "#!/usr/bin/env ruby\n# #{name}\n\n# 20261022\n# #{version}\n\nputs 'widget'\n"
end

def released_files(version)
  {'CHANGELOG' => changelog(version), 'bin/widget' => program('widget', version)}
end

def commit_files(subject, files = {})
  files.each do |path, content|
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
  git('add', '--all')
  git('commit', '--allow-empty', '-m', subject)
end

def release(version, files = released_files(version))
  commit_files("#{version}: The release.", files)
  git('push', 'origin', 'master')
end

def in_clone
  Dir.mktmpdir do |directory|
    Dir.chdir(directory) do
      git('init', '--bare', '-b', 'master', 'widget.git')
      git('clone', 'widget.git', 'widget')
      Dir.chdir('widget'){yield}
    end
  end
end

def tag_version(*arguments)
  stdout, stderr, status = Open3.capture3(BIN, *arguments)
  [status.exitstatus, stdout + stderr]
end

describe 'git-tag-version' do
  it "tags HEAD v<version>, signed, with the subject as the message, and pushes the tag" do
    in_clone do
      release('0.1.0')
      status, output = tag_version
      _(status).must_equal 0
      _(output).must_include "Tagged #{sha('HEAD')[0, 7]} v0.1.0 and pushed it to origin."
      _(tag_object('v0.1.0')).must_match(/^type commit$/)
      _(tag_object('v0.1.0')).must_include "\n\n0.1.0: The release.\n-----BEGIN PGP SIGNATURE-----"
      _(sha('v0.1.0')).must_equal sha('HEAD')
      _(origin_tag_commit('v0.1.0')).must_equal sha('HEAD')
    end
  end

  it 'tags the commit given rather than HEAD' do
    in_clone do
      release('0.1.0')
      release_commit = sha('HEAD')
      commit_files('+ TODO', 'TODO' => "# TODO\n")
      git('push', 'origin', 'master')
      status, _ = tag_version('HEAD~1')
      _(status).must_equal 0
      _(sha('v0.1.0')).must_equal release_commit
      _(origin_tag_commit('v0.1.0')).must_equal release_commit
    end
  end

  it 'stops where the subject has no version' do
    in_clone do
      release('0.1.0')
      commit_files('+ TODO', 'TODO' => "# TODO\n")
      git('push', 'origin', 'master')
      status, output = tag_version
      _(status).must_equal 1
      _(output).must_include "HEAD's subject has no version"
      _(`git tag`).must_be_empty
    end
  end

  it 'stops where there is no such commit' do
    in_clone do
      release('0.1.0')
      status, output = tag_version('nonesuch')
      _(status).must_equal 1
      _(output).must_include 'There is no commit nonesuch.'
    end
  end

  it 'stops where there is no remote called origin' do
    in_clone do
      release('0.1.0')
      git('remote', 'remove', 'origin')
      status, output = tag_version
      _(status).must_equal 1
      _(output).must_include 'There is no remote called origin.'
      _(`git tag`).must_be_empty
    end
  end

  it 'stops where given more than one commit' do
    in_clone do
      release('0.1.0')
      status, output = tag_version('HEAD', 'HEAD')
      _(status).must_equal 1
      _(output).must_include 'Usage: git tag-version'
    end
  end

  it 'stops where the commit is on no branch of origin' do
    in_clone do
      release('0.1.0')
      commit_files('0.1.1: Not pushed.', released_files('0.1.1'))
      status, output = tag_version
      _(status).must_equal 1
      _(output).must_include "#{sha('HEAD')[0, 7]} isn't on any branch of origin"
      _(`git tag`).must_be_empty
    end
  end

  describe 'the CHANGELOG' do
    it 'stops where its newest entry names another version' do
      in_clone do
        release('0.1.0', 'CHANGELOG' => changelog('0.0.9'))
        status, output = tag_version
        _(status).must_equal 1
        _(output).must_include 'HEAD is 0.1.0, but CHANGELOG names 0.0.9. Nothing tagged.'
        _(`git tag`).must_be_empty
      end
    end

    it 'reads the newest of several entries under one date' do
      in_clone do
        release('0.1.1', 'CHANGELOG' => "# CHANGELOG\n\n## 20261022\n\n0.1.1: Later.\n\n1. ~ x\n\n0.1.0: Earlier.\n\n1. + y\n")
        status, _ = tag_version
        _(status).must_equal 0
      end
    end

    it 'reads ## x.y.z (date) headings' do
      in_clone do
        release('0.1.0', 'CHANGELOG.md' => "# CHANGELOG\n\n## 0.1.0 (20261022): The release.\n\n## 0.0.9 (20261021): Before.\n")
        status, _ = tag_version
        _(status).must_equal 0
      end
    end

    it 'reads ## [x.y.z] headings' do
      in_clone do
        release('0.1.0', 'CHANGELOG' => "# CHANGELOG\n\n## [0.1.0] - 2026-10-22\n\n## [0.0.9] - 2026-10-21\n")
        status, _ = tag_version
        _(status).must_equal 0
      end
    end

    it 'stops where it names no version' do
      in_clone do
        release('0.1.0', 'CHANGELOG' => "# CHANGELOG\n\n## Unreleased\n")
        status, output = tag_version
        _(status).must_equal 1
        _(output).must_include 'CHANGELOG names no version'
      end
    end

    it 'is read at the commit, not from the working tree' do
      in_clone do
        release('0.1.0', 'CHANGELOG' => changelog('0.0.9'))
        File.write('CHANGELOG', changelog('0.1.0'))
        status, _ = tag_version
        _(status).must_equal 1
      end
    end
  end

  describe "the program's header" do
    it 'stops where it names another version' do
      in_clone do
        release('0.1.0', 'CHANGELOG' => changelog('0.1.0'), 'bin/widget' => program('widget', '0.0.9'))
        status, output = tag_version
        _(status).must_equal 1
        _(output).must_include "HEAD is 0.1.0, but bin/widget's header names 0.0.9. Nothing tagged."
      end
    end

    it 'names every disagreement' do
      in_clone do
        release('0.1.0', released_files('0.0.9'))
        status, output = tag_version
        _(status).must_equal 1
        _(output).must_include "but CHANGELOG names 0.0.9, and bin/widget's header names 0.0.9."
      end
    end

    it 'is read from a program at the top of the repository' do
      in_clone do
        release('0.1.0', 'CHANGELOG' => changelog('0.1.0'), 'widget' => program('widget', '0.0.9'))
        status, output = tag_version
        _(status).must_equal 1
        _(output).must_include "widget's header names 0.0.9"
      end
    end

    it 'is not read from other programs, which carry versions of their own' do
      in_clone do
        release('0.1.0', released_files('0.1.0').merge('bin/helper' => program('helper', '0.0.1')))
        status, _ = tag_version
        _(status).must_equal 0
      end
    end

    it 'is passed over where the program has no dated header' do
      in_clone do
        release('0.1.0', 'CHANGELOG' => changelog('0.1.0'), 'bin/widget' => "#!/usr/bin/env ruby\nputs 'widget'\n")
        status, _ = tag_version
        _(status).must_equal 0
      end
    end

    it 'stops where a dated header names no version' do
      in_clone do
        release('0.1.0', 'CHANGELOG' => changelog('0.1.0'), 'bin/widget' => "#!/usr/bin/env ruby\n# widget\n\n# 20261022\n\nputs 'widget'\n")
        status, output = tag_version
        _(status).must_equal 1
        _(output).must_include "bin/widget's header names no version"
      end
    end
  end

  describe "the gem's version" do
    it 'stops where the VERSION constant the gemspec names is another version' do
      in_clone do
        release('0.1.0', 'CHANGELOG' => changelog('0.1.0'), 'widget.gemspec' => "Gem::Specification.new do |spec|\n  spec.version = Widget::VERSION\nend\n", 'lib/Widget/VERSION.rb' => "module Widget\n  VERSION = '0.0.9'\nend\n")
        status, output = tag_version
        _(status).must_equal 1
        _(output).must_include 'but lib/Widget/VERSION.rb names 0.0.9.'
      end
    end

    it 'agrees where the VERSION constant is the same version' do
      in_clone do
        release('0.1.0', 'CHANGELOG' => changelog('0.1.0'), 'widget.gemspec' => "Gem::Specification.new do |spec|\n  spec.version = Widget::VERSION\nend\n", 'widget.rb.gemspec' => "Gem::Specification.new do |spec|\n  spec.version = Widget::VERSION\nend\n", 'lib/Widget/VERSION.rb' => "module Widget\n  VERSION = '0.1.0'\nend\n")
        status, _ = tag_version
        _(status).must_equal 0
      end
    end

    it 'stops where a literal version in the gemspec is another version' do
      in_clone do
        release('0.1.0', 'CHANGELOG' => changelog('0.1.0'), 'widget.gemspec' => "Gem::Specification.new do |s|\n  s.version = \"0.0.9\"\nend\n")
        status, output = tag_version
        _(status).must_equal 1
        _(output).must_include 'but widget.gemspec names 0.0.9.'
      end
    end
  end

  describe 'where the tag exists already' do
    it 'does nothing where it names the commit, here and on origin' do
      in_clone do
        release('0.1.0')
        tag_version
        tag = tag_object('v0.1.0')
        status, output = tag_version
        _(status).must_equal 0
        _(output).must_include 'v0.1.0 already names'
        _(output).must_include 'Nothing to do.'
        _(tag_object('v0.1.0')).must_equal tag
      end
    end

    it 'pushes it where it names the commit and origin has not got it' do
      in_clone do
        release('0.1.0')
        git('tag', '-a', '-m', '0.1.0: The release.', 'v0.1.0')
        status, output = tag_version
        _(status).must_equal 0
        _(output).must_include 'Pushed it to origin.'
        _(origin_tag_commit('v0.1.0')).must_equal sha('HEAD')
      end
    end

    it 'fetches it where only origin has it and it names the commit' do
      in_clone do
        release('0.1.0')
        git('tag', '-a', '-m', '0.1.0: The release.', 'v0.1.0')
        git('push', 'origin', 'v0.1.0')
        git('tag', '-d', 'v0.1.0')
        status, output = tag_version
        _(status).must_equal 0
        _(output).must_include 'Fetched it.'
        _(sha('v0.1.0')).must_equal sha('HEAD')
      end
    end

    it 'stops where it names another commit' do
      in_clone do
        release('0.1.0')
        git('tag', '-a', '-m', '0.1.0: The release.', 'v0.1.0', 'HEAD')
        release('0.1.0', 'CHANGELOG' => changelog('0.1.0') + "\n")
        status, output = tag_version
        _(status).must_equal 1
        _(output).must_include "v0.1.0 already names #{sha('HEAD~1')[0, 7]}, not #{sha('HEAD')[0, 7]}."
        _(origin_tag_commit('v0.1.0')).must_be_nil
      end
    end

    it 'stops where origin has it naming another commit' do
      in_clone do
        release('0.1.0')
        git('tag', '-a', '-m', '0.1.0: The release.', 'v0.1.0')
        git('push', 'origin', 'v0.1.0')
        git('tag', '-d', 'v0.1.0')
        release('0.1.0', 'CHANGELOG' => changelog('0.1.0') + "\n")
        status, output = tag_version
        _(status).must_equal 1
        _(output).must_include "v0.1.0 already names #{sha('HEAD~1')[0, 7]} on origin"
        _(`git tag`).must_be_empty
      end
    end
  end
end
