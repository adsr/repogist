# repogist

Like [gist](https://github.com/defunkt/gist), but backed by a normal repository.
Useful if you want private gists.

GitHub currently doesn't support private gists. There are _secret_ gists, which
are unlisted, but they are viewable by anyone that knows the URL.

repogist tries to behave and support flags similar to gist.

repogist uses the [octokit.rb](https://github.com/octokit/octokit.rb) library to
interface with the GitHub API.

### Synopsis

```console
$ repogist --help
Usage: repogist [options] [filename]
Usage: ... | repogist [options]

    -f, --filename=FNAME             Sets the filename and syntax type.
    -t, --type=EXT                   Sets the file extension and syntax type.
    -d, --description=DESC           Adds a description to your gist (commit message).
        --skip-empty                 Skip gisting empty files
    -v, --version                    Print the version.
    -h, --help                       Show this message.
...
$ git diff | repogist -t diff
https://github.com/adsr/gists/blob/199f769/content/adam/6f7ff7caa30d4d17.diff
$ repogist repogist.rb 
https://github.com/adsr/gists/blob/4031ccb/content/adam/repogist.rb
```

### Configuration

##### GitHub config

* Create a GitHub repo named "gists" or whatever you want
* Create a GitHub app named "repogist" or whatever you want (`[profile avatar] -> Settings > Developer Settings > New GitHub app`)
* In app settings:
  * Under "General", note the `App ID`
  * Under "General", generate a private key and save it
  * Under "Permissions & events", grant it repo-level perms:
    * "Contents" - Read/write
    * "Metadata" - Read-only (This is enabled by default)
  * Under "Install App"
    * Install the app to whatever account owns your "gists" repo
    * Grant it access to just the "gists" repo
* Back at your "gists" repo, go to `Settings > GitHub Apps` and click `Configure` next to the "repogist" app
  * Note the `installation_id` from the URL (`https://github.com/settings/installations/<installation_id>`)

##### Local config

* Install repogist
  * `git clone https://github.com/adsr/repogist`
  * Install deps
    * Option 1: via `gem` to a local `vendor/` directory: `make gem`
    * Option 2: via `bundle`: `bundle install` (root maybe required, depending on `GEM_HOME`)
  * Optionally, add repogist directory to `PATH` (or symlink `/usr/bin/repogist` or `~/bin/repogist` to `repogist.rb`)
* Configure repogist
  * At `~/.config/repogist/repogist.yml` or `/etc/repogist.yml`:
    ```yaml
    ---
    app_id: <app_id>
    private_key: |
      -----BEGIN RSA PRIVATE KEY-----
      ...
      -----END RSA PRIVATE KEY-----
    installation_id: <installation_id>
    repo_name: <owner>/<repo>
    repo_branch: <branch>
    ```

### Details

* repogist adds files to `content/<username>/<filename>` in the "gists" repo.
* `<filename>` is generated randomly if one isn't specified.
* If the target path already exists in the repo, it is updated.
* Commit messages are formatted like `<username> on <hostname> @ <timestamp>`
  with a description appended if specified.

### TODO

```console
$ grep -i todo repogist.rb | sed -E 's/^\s+//g'
# TODO: Support other gist flags
# TODO: Read multiple files?
# TODO: Delete gist?
# TODO: Custom filename format
# TODO: Custom commit message format
```
