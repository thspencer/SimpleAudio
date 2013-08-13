#! /usr/bin/env perl

#   SimpleAudio
#   Copyright (c) 2013, Taylor Spencer <taylorspencer@gmail.com>
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see <http://www.gnu.org/licenses/>.
#

# simple script to convert any FFmpeg compatible audio format to any other FFmpeg compatible audio format
# using defaults this script will convert any matched DTS audio stream to AC3 (5.1 channels or lower)

# input:   some media file with audio and or video (searches for DTS audio by default)
# output:  audio file (AC3 default)
# requires a pre-compiled FFmpeg (or compatible) binary, and of course Perl
# tested and functions on Mac OS X 10.8, most likely compatible with any POSIX compatible system

use strict;
use warnings;

my $TITLE   = "SimpleAudio";
my $VERSION = "0.1.2";
my $USAGE   = "\tusage: $0 [input options] [output options]\n\tuse -h for full help\n";

# Print script information header
print "\n$TITLE: version $VERSION, ";
print "Copyright (c) 2013 Taylor Spencer\n";

##########  PARAMETER DEFAULTS  ##########
my $debug           = 0;            # enable additional output
my $replace_file    = 0;            # overwrite input file
my $lang            = "eng";        # language code to search for
my $audio_src       = "dts|dca";    # codec to convert audio stream from
my $audio_dst       = "ac3";        # codec to convert audio stream to
my $audio_br        = "640k";       # bitrate for audio conversion
my $audio_ch        = 0;            # number of audio channels to downmix to
my $container       = "ac3";        # container format to use for output
my $threads         = 0;            # 0-16, number of CPU cores FFmpeg should use, 0=auto

my $ffmpeg;         # path to FFmpeg executable
my $input_file;     # input file source
my $output_file;    # output file destination
my $stream;         # matched audio stream
my $cmd;            # command to execute
my @returned;       # stores executable output
my $match;          # matching audio stream
##########  END DEFAULTS  ##########

##########  BEGIN MAIN  ##########

# Parse arguments
getOpts();

# Search ENVPATH for conversion binary if no value given
# FFmpeg is the default utility looked for
unless ( $ffmpeg && -e $ffmpeg ){
    $ffmpeg = getBin( 'ffmpeg' );
    print "using '$ffmpeg'\n" if $ffmpeg;
}

# Determine input file
# Exit if no value given
unless ( $input_file ){
  die "error: input file not defined\n\t$USAGE\n";
}

# Determine output file
# If no value given then use input filename and add new extension
if ( !$output_file ){
  $output_file = "$input_file.$container";
}

# Probe input file
probe();

# Check for matching stream
unless ( $match ){
    print "warning, file contained no $audio_src streams\n";
} else {
    print "converting audio found in stream $stream from '$audio_src' to '$audio_dst'\n";
}

# Convert audio stream and check return status code
unless ( convert() && !$? ){
    print "error: unable to convert $input_file\n";
    printDebug();
    die "\n";
}

# Print any final debug messages after execution completes
printDebug() if $debug;

# EXIT
print "\n...done\n";
exit;

##########  END MAIN  ##########

# Parse command line options
sub getOpts{
    unless ( @ARGV ){
        print $USAGE;
        exit;
    } else {
        for ( my $i = 0; $i < scalar( @ARGV ); $i++ ){
            if ( $ARGV[$i] =~ m/-h/i ){
                printOpts();
                exit;

            } elsif ( $ARGV[$i] =~ m/-ffpath/i ){
                $ffmpeg = $ARGV[++$i];

            } elsif ( $ARGV[$i] =~ m/-threads/i ){
                $threads = $ARGV[++$i];

            } elsif ( $ARGV[$i] =~ m/-lang/i ){
                $lang = $ARGV[++$i];

            } elsif ( $ARGV[$i] =~ m/-audio_src/i ){
                $audio_src = $ARGV[++$i];

            } elsif ( $ARGV[$i] =~ m/-audio_dst/i ){
                $audio_dst = $ARGV[++$i];

            } elsif ( $ARGV[$i] =~ m/-audio_br/i ){
                $audio_br = $ARGV[++$i];

            } elsif ( $ARGV[$i] =~ m/-audio_ch/i ){
                $audio_ch = $ARGV[++$i];

            } elsif ( $ARGV[$i] =~ m/-format/i ){
                $container = $ARGV[++$i];

            } elsif ( $ARGV[$i] =~ m/-in/i ){
                $input_file = $ARGV[++$i];

            } elsif ( $ARGV[$i] =~ m/-out/i ){
                $output_file = $ARGV[++$i];

            } elsif ( $ARGV[$i] =~ m/-replace_file/i ){
                $replace_file = $ARGV[++$i];

            } elsif ( $ARGV[$i] =~ m/-debug/i ){
                $debug = 1; # Turn on debug output

            } else {
                print "\tinvalid argument: $ARGV[$i]\n";
                print "\tuse -h to get full help\n";
                exit;
            }
        }
    }
}

# Search ENVPATH for conversion binary (FFmpeg by default)
sub getBin{
    my $bin = $_[0];
    foreach my $path ( split(/:/, $ENV{'PATH'} )){
        return $path."/$bin" if ( -e "$path/$bin" );
    }
    # try to run binary directly as last resort
    unless ( `$bin 2>&1` ){
        die "error: $bin binary not found\n";
    }
    return $bin
}

# Probe input file to find matching audio streams
sub probe{
    # Determine if input file exists and is readable
    unless ( -f -e $input_file ) {
        die "error: input file does not exist or is not readable\n";
    }

    # Command to execute
    my $cmd = join " ",
                $ffmpeg,
                "-i", "'$input_file'"
            ;
    # Execute command
    @returned = `$cmd 2>&1`;

    # Process output for matches
    foreach my $line( @returned ){
        if ( $line =~ m/stream.*(\d+:\d+).*$audio_src.*$lang/i ){
            $stream = $1;
            $match = $match.$line;
            return;

        } elsif ( $line =~ m/no such file/i ){
            print "error: $ffmpeg was unable to probe input file\n";
            die "\t$line\n";
        }
    }
}

# Convert matched stream to desired format
sub convert{
    $cmd = join " ",
            $ffmpeg,
            "-n",                           # overwrite file if exists?
            "-i", "'$input_file'",          # input
            "-vn",                          # ignore video stream
            "-codec:a:$stream", $audio_dst, # audio output format
            "-b:a:$stream", $audio_br,      # audio output bitrate
            "-sn",                          # ignore subtitles
            "-threads", $threads,           # CPU threads to use
            "-f", $container,               # audio output container format
            "'$output_file'"                # output
           ;
    # Execute command
    @returned = `$cmd 2>&1`;
}

# Print debug information and any messages from conversion binary
sub printDebug{
    print "\nDEBUG OUTPUT";
    print "\nInput file:\n\t$input_file"    if $input_file;
    print "\nOutput file:\n\t$output_file"  if $output_file;
    print "\nConversion arguments:\n\t$cmd" if $cmd;

    if ( $audio_src ){
        print "\nAudio streams matching '$audio_src':";
        print $stream ? "\n\t$stream\n" : "\n\tnone\n";
    }

    if ( @returned ){
        print "\nFFmpeg output:\n";
        foreach my $line( @returned ){
            print "\t$line";
        }
    }
}

# Print full help options
sub printOpts{
    print
        $USAGE,
        "Argument\tValue\t\t\tUse: '*' notes a required option\n",
        "--------\t-----\t\t\t--------------------------------\n",
        "-ffpath\t\t'/path/to/ffmpeg'\t FFmpeg (or compatible) binary, default: search system ENVPATH\n",
        "-threads\t0 to 16\t\t\t number of threads to use with FFmpeg, default: 0(auto)\n",
        "-lang\t\tstring\t\t\t preferred languange when multiple audio streams exist, default:'eng'\n",
        "-audio_src\tstring\t\t\t codec to convert audio from, default:'$audio_src'\n",
        "-audio_dst\tstring\t\t\t codec to convert audio stream to, default:'$audio_dst'\n",
        "-audio_br\tinteger\t\t\t bitrate to use in audio conversion, default:'640k'\n",
        "-audio_ch\tinteger\t\t\t number of channels to use if downmixing audio, default: same\n",
        "-format\t\tstring\t\t\t container type for output file, default:$container\n",
        "-in\t\t'/path/to/input'\t*input file path\n",
        "-out\t\t'/path/to/output'\t default: same as input with container type extension\n",
        "-replace_file\tempty\t\t\t overwrite original input file, default: disabled\n",
        "-debug\t\tempty\t\t\t enable verbose logging and output summary\n",
    ;
}
