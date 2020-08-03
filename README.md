## PURPOSE

Hack timestamp support into Git via 3rd party scripts.  Set the author/commit
dates for each file to the original timestamp of the file, so that the
timestamp may be later restored locally via Rodrigo Silva's
[git-restore-mtime](https://github.com/MestreLion/git-tools) tool.

If a file exists in the current HEAD and the local timestamp is older than
the current version in the repository, do not override the dates (use the
git default of current local time).

User-specified branches are not currently supported, the script simply
uses HEAD.

There is currently no special handling of merges.  'git-restore-mtime' has
several different options for handling merges, but until I better understand
the ramifications of those options on my use case, I'm just using the timestamp
that 'git log -1' chooses to report.  'git log -1 --no-merges' would probably
be closer to the 'git-restore-mtime' default parsing of 'git whatschanged'.

<BR>



## METHOD

Files are committed one-by-one.  The author/commit dates are back-dated by
setting the GIT_AUTHOR_DATE and GIT_COMMITTER_DATE enviroment variables prior
to the commit for each individual file.  Existing files older than the version
in the repository, as well as newly deleted files, are *NOT* back-dated.
Files are committed in chronological order, oldest to newest.  Files with
tied timestamps (such as deleted files) will commit in reverse alphabetical
order, so that they are displayed alphabetically in 'git log'.

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
repository timestamp, the commit proceeds using normal default commit date
behavior (we don't want new changes to the file being dated before the prior
versions).

The commit message is generated from a combination of the (optional)
user-provided message, the operation to be performed (taken from its 'git
status' line), and the timestamp to be recorded (if author/commit dates are
altered in the future, we'll still have a record of the intended timestamp).
Semicolons are inserted between the user message, operation message, and
timestamp message, to improve readability in the project web interface.  To
preserve new line formatting, the message is piped to git using:
'echo -e -n 'message to commit' | git commit -F - "file to commit"'.

Generally, the timestamp message will simply be the timestamp of the local
file.  If the author/commit dates were NOT back-dated (the local timestamp was
older than the current version in the repository), then the timestamp message
will be the then-current local time, with " (local)" appended to indicate that
the then-current local time was used instead of the local timestamp.  If a
file is deleted, the timestamp is given as "[file deleted]", and if, for some
reason, the local timestamp cannot be determined, the timestamp message is
"[timestamp missing]" (the commit is not back-dated, since we cannot know
when to back-date it to).

<BR>



## SYNTAX

git_commit_timestamps.pl ['user message'] [--commit] [--force] [--query-ct]

If no 'user message' is specified, then only the auto-generated operation
and timestamp messages are recorded for each commit.  NOTE -- it is
recommended that you surround the message in single quotes, rather than
double quotes, to prevent undesired behavior due to multiple layers of
shell and escape interpreting.  'line1\nline2' will result in two separate
lines, while 'line\\nline2' would yield a single line consisting of
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
> echo "delete_me" > delete me
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
