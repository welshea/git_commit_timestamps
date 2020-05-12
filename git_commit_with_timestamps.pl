#!/usr/bin/perl -w

# TOFIX -- it looks like the git server is using local time, not GMT time
# so, when I set commit time to gmtime format, it's 4 hours off from 
# committing outside the script

use POSIX qw(strftime);


# run in root directory of current git project


# git doesn't wrap commit messages, either when commiting or displaying log.
#
# So, we'll need to do something like:
#    echo -e -n "line1\nline2\nline3\n" | git commit -F -
#
# I'll need to write a function to take the message to be commited,
#  line wrap it, then pipe it to git when committing
#



$dryrun_flag = 1;
$message_user_str = '';
for ($i = 0; $i < @ARGV; $i++)
{
    $field = $ARGV[$i];

    if ($field =~ /^--/)
    {
        if ($field eq '--dryrun')
        {
            $dryrun_flag = 1;
        }
        elsif ($field eq '--commit')
        {
            $dryrun_flag = 0;
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



# run git status to retrieve list of commits
$git_status_results = `git status -s -uno`;
$bad_status_flag = 0;
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

            $problem_flag = 1;
        }
        # staging out of sync
        elsif ($char_2 =~ /[MADRC]/ && $char_1 ne ' ')
        {
            $desynced_hash{$line} = 1;

            $problem_flag = 1;
        }
        
        if ($problem_flag)
        {
            $bad_status_flag = 1;
        }


        $commit_flag = 0;
        if ($char_1 =~ /[MADRC]/ && $char_2 eq ' ')
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
if (defined %desynced_hash)
{
    foreach $line (sort keys %desynced_hash)
    {
        print "DESYNCED   $line\n";
    }
}

# print unmerged files
if (defined %unmerged_hash)
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

if (!defined(%files_to_commit_hash))
{
    print "No files to commit\n";
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


# commit each file separately, changing the time stamp of each
foreach $file (@files_to_commit_array)
{
    $status_line     = $files_to_commit_hash{$file};
    $operation       = substr $status_line, 0, 1;
    $file_str        = substr $status_line, 3;
    $timestamp_str   = $iso_timestamp_hash{$file};
    $timestamp_mtime = $unix_timestamp_hash{$file};
    $timestamp_git   = '';
    $git_newer_flag  = 0;
    
    # should only occur on deleted files
    if (!defined($timestamp_str))
    {
        $timestamp_str = '';
    }

    if ($timestamp_str =~ /[0-9]/)
    {
        $ls_tree_head = `git ls-tree HEAD "$file" 2> /dev/null`;
        if ($ls_tree_head =~ /[A-Za-z0-9]/)
        {
            $timestamp_git = `git log -1 --pretty="format:%ct" "$file" 2>/dev/null`;
        }

        # file exists in repo already, check timestamp
        if ($timestamp_git =~ /[0-9]/)
        {
            # don't override date if git file is newer
            if ($timestamp_git >= $timestamp_mtime)
            {
                $git_newer_flag = 1;
            }
        }
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
            if ($git_newer_flag == 0)
            {
                $message_timestamp_str = sprintf "[%s]",
                    $timestamp_str;
            }
            # commit git server timestamp as usual, comment as local
            else
            {
                $iso_time_str = strftime("%c %z", localtime());

                $message_timestamp_str = sprintf "[%s] (local",
                    $iso_time_str;
            }
        }
        else
        {
            # timestamp wasn't found for some reason
            $message_timestamp_str = sprintf "[%s]",
                '[timestamp missing]';
        }
    }
    else
    {
        $message_timestamp_str = '[file deleted]';
    }
    
    # Merge all messages together
    # Although we format them nicely with newlines, the git website
    #  unwraps in its single line display, so put ';' at the end of each
    #  line, if there are multiple lines, to be more legible on the website.
    $message_final_str = '';
    if ($message_user_str =~ /\S/)
    {
        $message_final_str .= "$message_user_str";
    }
    if ($message_operation_str =~ /\S/)
    {
        if ($message_final_str =~ /\S/)
        {
            $message_final_str .= ";\n\n";
        }
        $message_final_str .= "$message_operation_str";
    }
    if ($message_timestamp_str =~ /\S/)
    {
        if ($message_final_str =~ /\S/)
        {
            $message_final_str .= ";\n";
        }
        $message_final_str .= "      $message_timestamp_str";
    }
    
    # remove trailing newline, since it just adds clutter
    $message_final_str =~ s/[\r\n]+$//;

    $message_final_str       = "\"$message_final_str\"";
    $message_final_str_print = $message_final_str;
    $message_final_str_print =~ s/\n/\\n/g;

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
    if ($operation =~ /^[MARC]/ &&
        $timestamp_str =~ /[0-9]/ &&
        $git_newer_flag == 0)
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
        $orig_file = $file_to_from_hash{$file};

        # commit the file
        if ($dryrun_flag == 0)
        {
            print "COMMIT: $message_operation_str\n";
            print "COMMIT:       $message_timestamp_str\n";

            `echo -e -n $message_final_str | git commit -F - "$orig_file" "$file"`;
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

            `echo -e -n $message_final_str | git commit -F - "$file"`;
        }
        else
        {
            print "DRYRUN: $message_operation_str\n";
            print "DRYRUN:       $message_timestamp_str\n";
        }
    }
}



if ($dryrun_flag)
{
    print "Re-run with --commit to commit the changes\n";
}
else
{
    print "Don't forget to check 'git log' and 'git status' to verify success\n"
}
