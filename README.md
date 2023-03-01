## PURPOSE

Hack timestamp support into Git via 3rd party scripts.  Set the author/commit
dates for each file to the original timestamp of the file, so that the
timestamp may be later restored locally via Rodrigo Silva's
[git-restore-mtime](https://github.com/MestreLion/git-tools) tool.

A file is not backdated in any of the following conditions: the file exists in
the current HEAD and the local timestamp is older than the current version in
the repository, the local timestamp is newer than the current local time (file
is dated in the local future), or the file is newly deleted.  In these cases,
git commit times are left unaltered, and the commit message includes the
current local time instead of the file's local timestamp.

User-specified branches are not currently supported, the script simply
uses HEAD.  Pointing HEAD to another branch or commit *might* produce the
expected results with this script, or it might not.  I haven't tested it, as I
am a relatively new user of Git and haven't "branched out" into branches yet.
For example, there are probably some edge cases that would require peerig into
the future and/or past on other branches that aren't going to be handled
correctly....

There is currently no special handling of merges.  'git-restore-mtime' has
several different options for handling merges, but until I better understand
the ramifications of those options on my use case, I'm just using the timestamp
that 'git log -1' chooses to report.  'git log -1 --no-merges' would probably
be closer to the 'git-restore-mtime' default parsing of 'git whatschanged'.

<BR>



## METHOD

Files are committed one-by-one.  The author/commit dates are backdated by
setting the GIT_AUTHOR_DATE and GIT_COMMITTER_DATE enviroment variables prior
to the commit for each individual file.  Existing files older than the version
in the repository, local-future dated files, and newly deleted files are *NOT*
backdated.  Files are committed in chronological order, oldest to newest.
Files with tied timestamps (such as deleted files) will commit in reverse
alphabetical order, so that they are displayed alphabetically in 'git log'.

'git status -s -uno' is run and parsed to retrieve the list of files Git plans
to commit.  The status of each file is printed before aborting or proceeding
further.  If Git has tracked changes to both the indexed (staged) version of
the file and the work tree (unstaged) version of the file, the script will
abort.  The user will need to resolve these conflicts before the script will
proceed any further.  Files with staging/merging conflicts are listed as
"DESYNCED" or "UNMERGED", respectively, while files the script will later
commit are listed as "GIT_TODO".  De-synced files can generally be resolved
by issuing 'git add -A "filename"' or 'git reset -- "filename"' commands, as
appropriate.  The --force option can be specified to override DESYNCED issues
and force them to be committed (UNMERGED issues will still abort).

'git ls-tree HEAD "filename"' is then used to check to see if a file already
exists in the current HEAD of the repository.  If the file exists, then
`git log -1 --pretty="format:%at" "filename"' is used to retrieve the last
author/commit dates of the file.  If the local timestamp is older than the
repository timestamp (we don't want new changes to the file being dated before
the prior versions), or in the local future (we want to limit timestamps in
the git server future as much as possible), the commit proceeds using normal
default commit date behavior .

The commit message is generated from a combination of the (optional)
user-provided message, the operation to be performed (taken from its 'git
status' line), and the timestamp to be recorded (if author/commit dates are
altered in the future, we'll still have a record of the intended timestamp).
Semicolons are inserted between the commit message, operation message, and
timestamp message, to improve readability in the project web interface.  To
preserve new line formatting, the message is piped to git using:
'echo -e -n 'message to commit' | git commit -F - "file to commit"'.

Generally, the timestamp message will simply be the timestamp of the local
file.  If the author/commit dates were NOT backdated (the local timestamp was
older than the current version in the repository, or in the local future),
then the timestamp message will be the then-current local time, with
" (local)" appended to indicate that the then-current local time was used
instead of the local timestamp.  If a file is deleted, the timestamp is given
as "[file deleted]".  If, for some reason, the local timestamp cannot be
determined, the timestamp message is set to "[timestamp missing]" and the
commit is not backdated, since we cannot know when to backdate it to.

I found an edge case recently that I can't do much about.  I touched some
soft links (touch -h) to indicate that the content of the files they point to
had changed.  I wanted to commit the re-dated soft links with a new commit
message regarding the changes to the files that they point to.  Even though
the timestamp had changed, and the content of the files they link to had
changed, git refused to stage the re-dated soft links, since it considered
them to be unchaged (they still point the same file names).  The workaround
was to 'git rm' each soft link, 'git add .', commit, recreate each soft link,
'git add .' again, then commit again with the originally intended commit
message.  Git was apparently too smart for its own good, and, instead of using
the fresh time stamps of the re-created soft links that were newly staged, the
timestamps it reported to my script were the previously touched timestamps the
links had prior to 'git rm'.  So, the 'git rm' commit is 12 minutes in the
future of the incorrectly-cached dates of the new re-linked soft links that
were committed afterwards.  Argh, stupid git.  Maybe I should have 'git reset'
after the first attempt that refused to stage them?  Why would git remember
the timestamps of the files prior to the 'git rm' instead of using the newer
timestamps after the files were re-created and re-staged?  Sigh.

<BR>



## SYNTAX

git_commit_timestamps.pl ['commit message'] [--commit] [--force] [--no-backdate] [--query-ct]

If no 'commit message' is specified, then only the auto-generated operation
and timestamp messages are recorded for each commit.  NOTE -- it is
recommended that you surround the message in single quotes, rather than
double quotes, to prevent undesired behavior due to multiple layers of
shell and escape interpreting.  'line1\nline2' will result in two separate
lines, while 'line\\\\nline2' would yield a single line consisting of
'line1\nline2'.

If --commit is not specified, then the script performs a "dry run", where
it summarizes the operations and auto-generated messages it plans to perform
("DRYRUN:" lines).  It is recommended that you always perform a dry run first,
before you commit, to be sure that the planned commits are what you intended.
Thus, a dry run is the default, and --commit must be additionally specified in
order for the operations to actually be committed.  "DRYRUN:" lines will
change to "COMMIT:" lines to indicate that a commit was requested.

The --force option should be used with caution.  Git can detect and commit
changes in unexpected ways when the staged and unstaged versions of the file
are both different from the repository, so make *absolutely sure* git has
correctly detected the changes that you intended to commit before you commit
them (run without --commit first, carefully inspect the "DRYRUN:" lines).

Use --query-ct to query the repository for commit time, instead of author
time.  'git log' and 'git-restore-mtime' default to author time, and we agree
with this choice, so we default to using author time as well.

Timestamp preservation via commit backdating is disabled with the --no-backdate
flag.  The timestamp that would have been backdated is still contained in
the commit message.  All other script functionality is retained.  This can
be useful if you want to commit using standard git timestamp behavior,
but still want to keep track of the original timestamps in the commit messages.

No error checking is performed, so it is recommended that you check 'git log'
and 'git status' after you commit, to be sure that everything worked as
expected.


#### _Examples:_

\> git_commit_timestamps.pl 'test adding a file'
<pre>
  GIT_TODO   A  test_files/file1.txt
  DRYRUN: ADD:  test_files/file1.txt
  DRYRUN:       [Fri May  8 14:07:58 2020 -0400]

  User message:
  test adding a file

  Re-run with --commit to commit the changes
</pre>

Adding the --commit flag would result in the following git log entry:

<pre>
  Author: WelshEA <Eric.Welsh@moffitt.org>
  Date:   Fri May 8 14:07:58 2020 -0400

     test adding a file;

     ADD:  test_files/file1.txt;
           [Fri May  8 14:07:58 2020 -0400]
</pre>

Potentially unintended de-synced staging behavior:

<pre>
> echo "delete_me" > delete_me
> git add delete_me
> rm delete_me       # NOTE -- delete was performed outside of 'git rm'
> git_commit_timestamps.pl --force
   GIT_TODO   AD delete_me
   DESYNCED   AD delete_me
   DRYRUN: ADD:  delete_me
   DRYRUN:       [timestamp missing]
   WARNING    de-synced staged files detected, be sure git commits as intended
   Re-run with --commit to commit the changes
</pre>

<BR>



## AUTHOR

Eric A. Welsh (Eric.Welsh@moffitt.org)

<BR>

## License and Copyright

Copyright (C) 2020, Eric A. Welsh (Eric.Welsh@moffitt.org)<BR>
Licensed under the zlib license:

<pre>
This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgment in the product documentation would be
   appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.
</pre>
