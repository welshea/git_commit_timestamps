#!/usr/bin/perl -w

use POSIX qw(strftime);


# run in root directory of current git project


# git doesn't wrap commit messages, either when commiting or displaying log.
#
# So, we'll need to do something like:
#    echo -e -n 'line1\nline2\nline3\n' | git commit -F -
#
# I'll need to write a function to take the message to be commited,
#  line wrap it, then pipe it to git when committing
#


sub cmp_timestamps
{
    my $file_1  = $a;
    my $file_2  = $b;
    my $mtime_1 = $commit_hash{$file_1}{mtime};
    my $mtime_2 = $commit_hash{$file_2}{mtime};
    
    # set missing timestamps to bogus far-future dates, so they sort last
    if ($mtime_1 eq '')
    {
        $mtime_1 = 9E99;
    }
    if ($mtime_2 eq '')
    {
        $mtime_2 = 9E99;
    }
    
    if ($mtime_1 < $mtime_2) { return -1; }
    if ($mtime_1 > $mtime_2) { return  1; }
    
    # when tied, return reverse alphabetical order,
    # so that they are in alphabetical order when displayed with git log
    return ($file_2 cmp $file_1);
}


$current_local_mtime = time();

$message_user_str    = '';
$dryrun_flag         = 1;
$force_flag          = 0;
$desync_detected     = 0;
$query_ct_flag       = 0;
$opt_backdate_flag   = 1;

for ($i = 0; $i < @ARGV; $i++)
{
    $field = $ARGV[$i];

    if ($field =~ /^-/)
    {
        if ($field eq '--backdate')
        {
            $opt_backdate_flag = 1;
        }
        elsif ($field eq '--no-backdate')
        {
            $opt_backdate_flag = 0;
        }
        elsif ($field eq '--dryrun')
        {
            $dryrun_flag = 1;
        }
        elsif ($field eq '--commit')
        {
            $dryrun_flag = 0;
        }
        elsif ($field eq '--force')
        {
            $force_flag = 1;
        }
        elsif ($field eq '--use-ct')
        {
            $query_ct_flag = 1;
        }
        else
        {
            print STDERR "git_commit_timestamps.pl [options] [\'commit message\']\n";
            print STDERR "\n";
            print STDERR "   Options:\n";
            print STDERR "      --backdate     backdate commits to preserve timestamps (default)\n";
            print STDERR "      --no-backdate  disable backdating, keep all other functionality\n";
            print STDERR "      --commit       commit staged changes\n";
            print STDERR "      --dryrun       perform a dry run, do not commit (default)\n";
            print STDERR "      --force        ignore de-synced staging issues, commit anyways\n";
            print STDERR "      --query-ct     query repository commit time, rather than author time\n";
            print STDERR "\n";
            print STDERR "   Options and commit message can be given in any order\n";
            print STDERR "   Enclose the commit message in '' to ensure proper escape handling\n";
            print STDERR "\n";
            print STDERR "   Report bugs to <Eric.Welsh\@moffitt.org>\n";
            
            exit(1);
        }
    }
    else
    {
        if ($message_user_str eq '')
        {
            $message_user_str = $field;
        }
    }
}

if (!defined($message_user_str))
{
    $message_user_str = "";
}

# deal with escaped EOL characters within user message
# strip final EOL
$message_user_str =~ s/(?<!\\)\\n|\n/\n/g;;
$message_user_str =~ s/(?<!\\)\\r|\r/\r/g;;
$message_user_str =~ s/[\r\n]+$//;


# run git status to retrieve list of commits
$git_status_results = `git status -s -uno`;
$bad_status_flag    = 0;

if ($git_status_results =~ /\S/)
{
    @lines = split /\n/, $git_status_results;
    
    foreach $line (@lines)
    {
        $line =~ s/[\r\n]+//g;
        
        $char_1   = substr $line, 0, 1;
        $char_2   = substr $line, 1, 1;
        $file_str = substr $line, 3;
        
        $file_1   = $file_str;
        $file_2   = '';

        # extract out from/to file names
        # assume that neither file contains " -> " in its name...
        #
        if (($char_1 =~ /[RC]/ || $char_2 =~ /[RC]/) &&
            $file_str =~ / -> /)
        {
            @array = split / -> /, $file_str;

            $file_1 = $array[0];
            $file_2 = $array[1];
        }

        #de-quote escaped filenames, since we will add quotes later
        $file_1 =~ s/^\"(.*?)\"$/$1/;
        $file_2 =~ s/^\"(.*?)\"$/$1/;
        
        $problem_flag = 0;

        # unmerged
        if (($char_1 eq 'A' && $char_2 eq 'A') ||
            ($char_1 eq 'D' && $char_2 eq 'D') ||
            $char_1 eq 'U' || $char_2 eq 'U')
        {
            $unmerged_hash{$line} = 1;

            $problem_flag = 1;
        }
        # staging out of sync
        elsif ($char_1 =~ /[MADRC]/ && $char_2 ne ' ')
        {
            $desynced_hash{$line} = 1;
            $desync_detected      = 1;

            if ($force_flag == 0)
            {
                $problem_flag = 1;
            }
        }
        # staging out of sync
        elsif ($char_2 =~ /[MADRC]/ && $char_1 ne ' ')
        {
            $desynced_hash{$line} = 1;
            $desync_detected      = 1;

            if ($force_flag == 0)
            {
                $problem_flag = 1;
            }
        }
        
        if ($problem_flag)
        {
            $bad_status_flag = 1;
        }


        $commit_flag = 0;
        if ($char_1 =~ /[MADRC]/)
        {
            $commit_flag = 1;
        }
        if ($problem_flag)
        {
            $commit_flag = 0;
        }
        
        if ($commit_flag)
        {
            # file to be committed isn't copied or renamed
            if ($file_2 eq '')
            {
                $files_to_commit_hash{$file_1} = $line;
            }
            # the destination file is the file to commit
            else
            {
                $files_to_commit_hash{$file_2} = $line;
            }
            
            if ($file_2 ne '')
            {
#                $file_from_to_hash{$file_1} = $file_2;
                $file_to_from_hash{$file_2} = $file_1;
            }

#            printf "%s\t%s\t%s\t%s\n",
#                $char_1, $char_2, $file_1, $file_2;

             printf "GIT_TODO   %s\n", $line;
        }
    }
}

# print de-sycned files
if (%desynced_hash)
{
    foreach $line (sort keys %desynced_hash)
    {
        print "DESYNCED   $line\n";
    }
}

# print unmerged files
if (%unmerged_hash)
{
    foreach $line (sort keys %unmerged_hash)
    {
        print "UNMERGED   $line\n";
    }
}


if ($bad_status_flag)
{
    print STDERR "ABORT -- unmerged / de-synced staged files:\n";
    print STDERR "           suggest 'git add -A \"file\"' or 'git reset -- \"file\"' as appropriate\n";

    exit(2);
}

if (%files_to_commit_hash == 0)
{
    print "No files to commit\n";
    
    exit(0);
}



@files_to_commit_array = sort keys %files_to_commit_hash;


# get timestamps of local files
foreach $file (@files_to_commit_array)
{
    @file_stats_array = stat($file);
    $mtime = $file_stats_array[9];

#    @time_array = localtime($mtime);
#    $sec   = $time_array[0];
#    $min   = $time_array[1];
#    $hour  = $time_array[2];
#    $mday  = $time_array[3];		# N'th day of the month
#    $mon   = $time_array[4];
#    $year  = $time_array[5] + 1900;	# year; base-1900, so add 1900
##    $wday  = $time_array[6];		# N'th day of the week
##    $yday  = $time_array[7];		# N'th day of the year
##    $isdst = $time_array[8];

    # file must have been deleted?
    if (!defined($mtime))
    {
        $mtime        = '';
        $iso_time_str = '';
    }
    else
    {
        $iso_time_str = strftime("%c %z", localtime($mtime));
    }
    
    $iso_timestamp_hash{$file}  = $iso_time_str;
    $unix_timestamp_hash{$file} = $mtime;
}


# get ready to commit each file
foreach $file (@files_to_commit_array)
{
    $status_line      = $files_to_commit_hash{$file};
    $operation        = substr $status_line, 0, 1;
    $file_str         = substr $status_line, 3;
    $timestamp_str    = $iso_timestamp_hash{$file};
    $timestamp_mtime  = $unix_timestamp_hash{$file};
    $timestamp_git    = '';
    $no_backdate_flag = 0;
    $file_escaped     = quotemeta($file);
    
    # should only occur on deleted files
    if (!defined($timestamp_str))
    {
        $timestamp_str   = '';
    }
    if (!defined($timestamp_mtime))
    {
        $timestamp_mtime = '';
    }

    # get commit time of latest commit involving the file, if it ever existed
    if ($timestamp_str =~ /[0-9]/)
    {
        # default
        #
        # 'git log' and 'git-restore-mtime' default to author time,
        #  and author time is more robust to git altering commit times
        #  when no changes have occurred to the files themselves
        if ($query_ct_flag == 0)
        {
            $timestamp_git =
                `git log -1 --follow --pretty="format:%at" -- $file_escaped 2>/dev/null`;
        }
        # query commit time instead of author time
        else
        {
            $timestamp_git =
                `git log -1 --follow --pretty="format:%ct" -- $file_escaped 2>/dev/null`;
        }

        # file exists in repo already, check timestamp
        if ($timestamp_git =~ /[0-9]/)
        {
            # don't override date if git file is newer
            if ($timestamp_git >= $timestamp_mtime)
            {
                $no_backdate_flag = 1;
            }
        }

        # file is dated in the future, use current local time instead
        if ($timestamp_mtime > $current_local_mtime)
        {
            $no_backdate_flag = 1;
        }
        
        printf STDERR "%s\t%s\n", $timestamp_git, $timestamp_mtime;
    }
    # make sure the invalid time variables are blanked out
    else
    {
        $timestamp_mtime = '';
        $timestamp_str   = '';
    }

    # comment operation performed on each committed file
    $message_operation_str = '';
    if    ($operation eq 'M')
    {
        $message_operation_str = sprintf "MOD:  %s", $file;
    }
    elsif ($operation eq 'A')
    {
        $message_operation_str = sprintf "ADD:  %s", $file;
    }
    elsif ($operation eq 'D')
    {
        $message_operation_str = sprintf "DEL:  %s", $file;
    }
    elsif ($operation eq 'R')
    {
        $message_operation_str = sprintf "REN:  %s", $file_str;
    }
    elsif ($operation eq 'C')
    {
        $message_operation_str = sprintf "CPY:  %s", $file_str;
    }
    
    # comment local timestamp
    $message_timestamp_str = '';
    if ($operation =~ /[MARC]/)
    {
        if ($timestamp_str =~ /[0-9]/)
        {
            # file is newer than repo, retro-date commit
            if ($no_backdate_flag == 0)
            {
                $message_timestamp_str = sprintf "[%s]",
                    $timestamp_str;
            }
            # commit git server timestamp as usual, comment as current local
            # overwrite local file timestamp internally
            else
            {
                $timestamp_mtime = $current_local_mtime;
                $timestamp_str   = strftime("%c %z",
                                            localtime($timestamp_mtime));

                $message_timestamp_str = sprintf "[%s] (local)",
                    $timestamp_str;
            }
        }
        else
        {
            # set time variables to current local time, since we don't know
            $timestamp_mtime  = $current_local_mtime;
            $timestamp_str    = strftime("%c %z",
                                         localtime($timestamp_mtime));
            $no_backdate_flag = 1;

            # timestamp wasn't found for some reason
            $message_timestamp_str = '[timestamp missing]';
        }
    }
    else
    {
        # set time variables to current local time, since we delete *NOW*
        $timestamp_mtime  = $current_local_mtime;
        $timestamp_str    = strftime("%c %z",
                                     localtime($timestamp_mtime));
        $no_backdate_flag = 1;

        $message_timestamp_str = '[file deleted]';
    }
    
    # Merge all messages together
    # Although we format them nicely with newlines, the git website
    #  unwraps in its single line display, so put ';' at the end of each
    #  line, if there are multiple lines, to be more legible on the website.
    $message_final_str = '';
    if ($message_user_str =~ /\S/)
    {
        $message_final_str .= $message_user_str;
    }
    if ($message_operation_str =~ /\S/)
    {
        if ($message_final_str =~ /\S/)
        {
            $message_final_str .= ";\n\n";
        }
        $message_final_str .= $message_operation_str;
    }
    if ($message_timestamp_str =~ /\S/)
    {
        if ($message_final_str =~ /\S/)
        {
            $message_final_str .= ";\n";
        }
        $message_final_str .= '      ' . $message_timestamp_str;
    }
    
    # remove trailing newline, since it just adds clutter
    $message_final_str =~ s/[\r\n]+$//;

    $commit_hash{$file}{mtime}             = $timestamp_mtime;
    $commit_hash{$file}{timestamp}         = $timestamp_str;
    $commit_hash{$file}{message_operation} = $message_operation_str;
    $commit_hash{$file}{message_timestamp} = $message_timestamp_str;
    $commit_hash{$file}{message_final}     = $message_final_str;
    $commit_hash{$file}{operation}         = $operation;
    $commit_hash{$file}{no_backdate}       = $no_backdate_flag;
}


if ($opt_backdate_flag == 0)
{
    printf STDERR "Disabling commit backdating, timestamps still in commit message\n";
}


# commit the files
foreach $file (sort cmp_timestamps keys %commit_hash)
{
    $timestamp_mtime       = $commit_hash{$file}{mtime};
    $timestamp_str         = $commit_hash{$file}{timestamp};
    $message_operation_str = $commit_hash{$file}{message_operation};
    $message_timestamp_str = $commit_hash{$file}{message_timestamp};
    $message_final_str     = $commit_hash{$file}{message_final};
    $operation             = $commit_hash{$file}{operation};
    $no_backdate_flag      = $commit_hash{$file}{no_backdate};
    $file_escaped          = quotemeta($file);

    # unset the date override environment variables
    if (defined($ENV{'GIT_AUTHOR_DATE'}))
    {
        delete $ENV{'GIT_AUTHOR_DATE'};
    }
    if (defined($ENV{'GIT_COMMITTER_DATE'}))
    {
        delete $ENV{'GIT_COMMITTER_DATE'};
    }
    
    # override current date with original file timestamp
    if ($opt_backdate_flag &&
        $operation =~ /^[MARC]/ &&
        $timestamp_str =~ /[0-9]/ &&
        $no_backdate_flag == 0)
    {
        # set git time environment variables
        $ENV{'GIT_AUTHOR_DATE'}    = $timestamp_str;
        $ENV{'GIT_COMMITTER_DATE'} = $timestamp_str;
    }
    
    # Special handling of renames:
    #
    #   The deleted file must be commited at the same time, rather than
    #   separately, otherwise the deleted/renamed file won't be linked and
    #   preserve its revision history, and the delete won't even get
    #   committed by the script at all (since there was no git status line
    #   for the deleted file)!
    #
    # We will assume that the deleted file isn't in the 'git status' list,
    # so it won't have already been committed elsewhere.  I might get
    # paranoid and check for this elsewhere, we'll see....
    #
    # We will assume that the renamed files only get detected as renamed
    # once.
    #
    # If there is a chain of renames, I'm not sure what will happen.
    #
    if ($operation eq 'R' && defined($file_to_from_hash{$file}))
    {
        $orig_file         = $file_to_from_hash{$file};
        $orig_file_escaped = quotemeta($orig_file);

        # commit the file
        if ($dryrun_flag == 0)
        {
            print "COMMIT: $message_operation_str\n";
            print "COMMIT:       $message_timestamp_str\n";

            `echo -e -n '$message_final_str' | git commit -F - $orig_file_escaped $file_escaped`;
        }
        else
        {
            print "DRYRUN: $message_operation_str\n";
            print "DRYRUN:       $message_timestamp_str\n";
        }
    }
    # regular single file commit
    else
    {
        # commit the file
        if ($dryrun_flag == 0)
        {
            print "COMMIT: $message_operation_str\n";
            print "COMMIT:       $message_timestamp_str\n";

            `echo -e -n '$message_final_str' | git commit -F - $file_escaped`;
        }
        else
        {
            print "DRYRUN: $message_operation_str\n";
            print "DRYRUN:       $message_timestamp_str\n";
        }
    }
}

# issue warning for long user messages that spill beyond 80 characters in
# 'git log;
if ($message_user_str =~ /\S/)
{
    @line_array = split /[\r\n]+/, $message_user_str;
    
    $long_line_flag = 0;

    foreach $line (@line_array)
    {
        if (length $line > 75)
        {
            $long_line_flag = 1;

            last;
        }
    }
}

if ($message_user_str =~ /\S/)
{
    if ($long_line_flag)
    {
        print "\n";
        printf STDERR "MESG_WARNING: %s\n",
            'user message > 75 characters wide, consider inserting newlines';
    }

    print "\n";
    print "User message:\n";


    print `echo -e '$message_user_str'`;
    print "\n";

}


if ($desync_detected && $force_flag)
{
    print STDERR "WARNING    de-synced staged files detected, be sure git commits as intended\n";
}

if ($dryrun_flag)
{
    print "Re-run with --commit to commit the changes\n";
}
else
{
    print "Don't forget to check 'git log' and 'git status' to verify success\n"
}
