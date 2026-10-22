# git-tag-version

## Description

Tag a release `v<version>`, signed, and push the tag to origin.

A release is a commit whose subject begins with its version, as `x.y.z: summary`, the same as release-audit reads it. The tag is annotated and signed, and its message is the commit's subject.

Before tagging, it reads the commit's own files, as they are at the commit rather than in the working tree, and stops where any of them names another version, so that a forgotten version bump is caught before it's tagged:

- the newest entry in the CHANGELOG (or CHANGELOG.md), being the first line which is `x.y.z: summary`, `## x.y.z (date)` or `## [x.y.z]`;
- the header of the program named after the repository, `bin/<name>` or `<name>`, where the version is the line under the date;
- the gem's version, where a gemspec gives it literally or as `<Constant>::VERSION`, read from `lib/<Constant>/VERSION.rb`.

Each is checked only where it's there. A CHANGELOG, a dated header or a VERSION.rb which is there and names no version stops it too.

## Installation

Put `bin/git-tag-version` somewhere on the PATH, and install the gems it needs:

```shell
$ gem install switches.rb git.rb
```

git runs any `git-<name>` on the PATH as `git <name>`.

## Usage

On the release commit, straight after merging it:

```shell
$ git tag-version
```

Or, to merge and tag in one go:

```shell
$ gh-ff-merge -d && git tag-version
```

To tag a commit other than HEAD:

```shell
$ git tag-version <commit>
```

It stops, tagging nothing, where:

- there is no remote called origin;
- there is no such commit;
- the commit's subject has no version;
- the CHANGELOG, the program's header or the gem's version names another version, or none;
- no branch of origin holds the commit, as far as this clone knows;
- `v<version>` already names another commit, here or on origin.

Where `v<version>` already names the commit, it pushes the tag if origin hasn't it, fetches it if only origin has it, and otherwise does nothing. A run which stopped part way, such as on a failed push, can be run again.

## Notes

1. It pushes to, and asks about tags on, the remote called origin.
2. Whether origin holds the commit is read from this clone's remote-tracking branches, without fetching. Straight after a merge which pushed, they're current.
3. The tag is signed with `git tag --sign`, whatever tag.gpgsign says.
4. A tag which already names the commit is taken as it is, whether or not it's annotated or signed.
5. The program is the one named after the repository on origin. Other programs in bin/ carry versions of their own, and aren't read.

## Contributing

1. Fork it... `https://github.com/thoran/git-tag-version/fork`
2. Create your feature branch... `git checkout -b my-new-feature`
3. Commit your changes... `git commit -am 'Add some feature'`
4. Push to the branch... `git push origin my-new-feature`
5. Create a new pull request


## License

MIT
