
package Bio::Path::Find::App::Role::Archivist;

# ABSTRACT: role providing methods for archiving data

use v5.10; # for "say"

use MooseX::App::Role;

=head1 CONTACT

path-help@sanger.ac.uk

=cut

use Cwd;
use Path::Class;
use File::Temp;
use Try::Tiny;
use IO::Compress::Gzip;
use Archive::Tar;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use Carp qw( carp );

use Bio::Path::Find::Exception;

use Types::Standard qw(
  ArrayRef
  +Str
  +Bool
);

use Bio::Path::Find::Types qw( :types );

with 'Bio::Path::Find::Role::HasProgressBar';

#-------------------------------------------------------------------------------
#- private attributes ----------------------------------------------------------
#-------------------------------------------------------------------------------

# set up "archive" like we set up "symlink". See also B::P::F::Role::Linker.

option 'archive' => (
  documentation => 'create a tar archive of data files',
  is            => 'rw',
  # no "isa" because we want to accept both Bool and Str
  cmd_aliases   => 'a',
  trigger       => \&_check_for_archive_value,
);

sub _check_for_archive_value {
  my ( $self, $new, $old ) = @_;

  if ( not defined $new ) {
    $self->_tar_flag(1);
  }
  elsif ( not is_Bool($new) ) {
    $self->_tar_flag(1);
    $self->_tar( file $new );
  }
  else {
    $self->_tar_flag(0);
  }
}

has '_tar_flag' => ( is => 'rw', isa => Bool );

has '_tar' => (
  is      => 'rw',
  isa     => PathClassFile,
  lazy    => 1,
  builder => '_build_tar_filename',
  clearer => '_clear_tar_filename',    # for use during testing
);

# specify the default tar file name here, so that it can be overridden by
# a method in a Lane that applies this Role
sub _build_tar_filename {
  my $self = shift;
  return file( 'pf_' . $self->_renamed_id . ( $self->no_tar_compression ? '.tar' : '.tar.gz' ) );
}

#---------------------------------------

# set up "zip" like we set up "symlink"

option 'zip' => (
  documentation => 'create a zip archive of data files',
  is            => 'rw',
  # no "isa" because we want to accept both Bool and Str
  cmd_aliases   => 'z',
  trigger       => \&_check_for_zip_value,
);

sub _check_for_zip_value {
  my ( $self, $new, $old ) = @_;

  if ( not defined $new ) {
    $self->_zip_flag(1);
  }
  elsif ( not is_Bool($new) ) {
    $self->_zip_flag(1);
    $self->_zip( file $new );
  }
  else {
    $self->_zip_flag(0);
  }
}

has '_zip_flag' => ( is => 'rw', isa => Bool );

has '_zip' => (
  is      => 'rw',
  isa     => PathClassFile,
  lazy    => 1,
  builder => '_build_zip_filename',
  clearer => '_clear_zip_filename',    # for use during testing
);

# specify the default zip file name here, so that it can be overridden by
# a method in a Lane that applies this Role
sub _build_zip_filename {
  my $self = shift;
  return file( 'pf_' . $self->_renamed_id . '.zip' );
}

#---------------------------------------

option 'no_tar_compression' => (
  documentation => "don't compress tar archives",
  is            => 'rw',
  isa           => Bool,
  cmd_flag      => 'no-tar-compression',
  cmd_aliases   => 'u',
);

#-------------------------------------------------------------------------------
#- private methods -------------------------------------------------------------
#-------------------------------------------------------------------------------

# make a tar archive of the data files for the found lanes

sub _make_tar {
  my ( $self, $data ) = @_;

  my $archive_filename = $self->_tar;

  say STDERR "Archiving data to '$archive_filename'";

  # collect the list of files to archive. $filenames is an array of hash refs,
  # each hash containing the path to a file as the key and an edited version of
  # the name as the key. The edited name is the one that should be used in the
  # archive that we're building here
  my ( $filenames, $stats ) = $self->_collect_filenames($data);

  # if the _collect_filenames method returned some statistics data, write a CSV
  # file with the stats and add it to the list of files that will go into the
  # archive
  my $stats_file;
  my $temp_dir = File::Temp->newdir; # create the temp directory outside of
                                     # the "if" block, otherwise it will be
  if ( defined $stats ) {            # prematurely removed...
    $stats_file = file( $temp_dir, 'stats.csv' );
    $self->_write_csv($stats, $stats_file);
  }

  # build the tar archive in memory
  my $tar = $self->_create_tar_archive($filenames, $stats_file);

  # we could write the archive in a single call, like this:
  #   $tar->write( $tar_filename, COMPRESS_GZIP );
  # but it's nicer to have a progress bar. Since gzipping and writing can be
  # performed as separate operations, we'll do progress bars for both of them

  # get the contents of the tar file. This is a little slow but we can't
  # break it down and use a progress bar, so at least tell the user what's
  # going on
  print STDERR 'Building tar file... ';
  my $tar_contents = $tar->write;
  print STDERR "done\n";

  # gzip compress the archive ?
  my $output = $self->no_tar_compression
             ? $tar_contents
             : $self->_compress_data($tar_contents);

  # and write it out
  $self->_write_data( $output, $archive_filename );

  #---------------------------------------

  # list the contents of the archive. Strip the path from stats.csv, since it's
  # a file that we generate in a temp directory. That temp dir is deleted as
  # soon as the leave this method, so it's meaningless to the end user of the
  # tar file
  say m|/stats.csv$| ? 'stats.csv' : keys %$_ for @$filenames;
}

#-------------------------------------------------------------------------------

# make a zip archive of the data files for the found lanes

sub _make_zip {
  my ( $self, $data ) = @_;

  my $archive_filename = $self->_zip;

  say STDERR "Archiving data to '$archive_filename'";

  # collect the list of files to archive. $filenames is an array of hash refs,
  # each hash containing the path to a file as the key and an edited version of
  # the name as the key. The edited name is the one that should be used in the
  # archive that we're building here
  my ( $filenames, $stats ) = $self->_collect_filenames($data);

  # write a CSV file with the stats, if there are any
  my $temp_dir = File::Temp->newdir;
  my $stats_file;
  if ( defined $stats ) {
    $stats_file = file( $temp_dir, 'stats.csv' );
    $self->_write_csv($stats, $stats_file);
  }

  #---------------------------------------

  # build the zip archive in memory
  my $zip = $self->_create_zip_archive($filenames, $stats_file);

  print STDERR 'Writing zip file... ';

  # write it to file
  if ( -e $archive_filename and not $self->force ) {
    Bio::Path::Find::Exception->throw(
      msg => qq(ERROR: output file "$archive_filename" already exists; not overwriting. Use "-F" to force overwriting)
    );
  }

  try {
    unless ( $zip->writeToFileNamed($archive_filename->stringify) == AZ_OK ) {
      print STDERR "failed\n";
      Bio::Path::Find::Exception->throw( msg => "ERROR: couldn't write zip file ($archive_filename)" );
    }
  } catch {
    Bio::Path::Find::Exception->throw( msg => "ERROR: error while writing zip file ($archive_filename): $_" );
  };

  print STDERR "done\n";

  #---------------------------------------

  # list the contents of the archive. Strip the path from stats.csv, since it's
  # a file that we generate in a temp directory. That temp dir is deleted as
  # soon as the file is archived, so it's meaningless to the user
  say m|/stats.csv$| ? 'stats.csv' : keys %$_ for @$filenames;
}

#-------------------------------------------------------------------------------

# retrieves the list of filenames associated with the supplied lanes. Returns
# two array refs.
#
# The first array contains a list of hashrefs, one for each file found by the
# lane. Each hash has the name of a file on disk as its key and an edited
# filename as the value. The edited filename is created by the
# "_edit_filenames" method on the file's lane, and is used as the name for the
# file in the archive.
#
# The second returned array contains the statistics for the lanes, with each
# row being an arrayref of stats for a lane.

sub _collect_filenames {
  my ( $self, $lanes ) = @_;

  my $pb = $self->_create_pb('collecting files', scalar @$lanes);

  # collect the lane stats as we go along. Store the headers for the stats
  # report as the first row
  my @stats = ( $lanes->[0]->stats_headers );

  my @filenames;
  foreach my $lane ( @$lanes ) {
    foreach my $from ( $lane->all_files ) {
      my $to = $lane->can('_edit_filenames')
             ? $lane->_edit_filenames($from, $from)
             : $from;
      push @filenames, { $from => $to };
    }
    push @stats, @{ $lane->stats };
    $pb++;
  }

  return ( \@filenames, \@stats );
}

#-------------------------------------------------------------------------------

# generates a new filename by converting hashes to underscores in the supplied
# filename. Also converts the filename to unix format, for use with tar and
# zip

sub _rename_file {
  my ( $self, $old_filename ) = @_;

  my $new_basename = file($old_filename)->basename;

  # honour the "--rename" option
  $new_basename =~ s/\#/_/g if $self->rename;

  # add on the folder to get the relative path for the file in the
  # archive
  my $folder_name = $self->_renamed_id;

  my $new_filename = file( $folder_name, $new_basename );

  # filenames in an archive are specified as Unix paths (see
  # https://metacpan.org/pod/Archive::Tar#tar-rename-file-new_name)
  $old_filename = file( $old_filename )->as_foreign('Unix');
  $new_filename = file( $new_filename )->as_foreign('Unix');

  $self->log->debug( "renaming |$old_filename| to |$new_filename|" );

  return $new_filename;
}

#-------------------------------------------------------------------------------

# creates an in-memory tar archive containing the specified files

sub _create_tar_archive {
  my ( $self, $files, $stats_file ) = @_;

  my $tar = Archive::Tar->new;

  my $pb = $self->_create_pb('adding files', scalar @$files);

  # the files are added with their full paths. We want them to be relative, so
  # we'll go through the archive and rename them all. If the "-rename" option
  # is specified, we'll also rename the individual files to convert hashes to
  # underscores
  foreach my $file ( @$files ) {
    my ( $from, $to ) = each %$file;
    keys %$file; # reset the "each" iterator, or next $from and $to are empty

    # put the real file into the archive
    $tar->add_files($from);

    # filenames in the archive itself are relative to the root directory, i.e.
    # they lack a leading slash. Trim off that slash before trying to rename
    # files in the archive, otherwise they're simply not found. Take a copy
    # of the original filename before we trim it, to avoid stomping on the
    # original
    ( my $trimmed_from = $from ) =~ s|^/||;

    # edit the "to" name to do things like changing hash to underscore
    my $renamed_to = $self->_rename_file($to);

    # and now, in the archive, change the name of the file from "from"
    # to "to"
    $tar->rename( $trimmed_from, $renamed_to )
      or carp "WARNING: couldn't rename '$trimmed_from' in archive";

    $pb++;
  }

  # add the stats file, if there is one
  if ( $stats_file ) {
    my $renamed_stats_file = file( $self->_renamed_id, 'stats.csv');
    $tar->add_files($stats_file);

    $stats_file =~ s|^/||;
    $tar->rename($stats_file, $renamed_stats_file);
  }

  return $tar;
}

#-------------------------------------------------------------------------------

# creates a ZIP archive containing the specified files

sub _create_zip_archive {
  my ( $self, $files, $stats_file ) = @_;

  my $zip = Archive::Zip->new;

  my $pb = $self->_create_pb('adding files', scalar @$files);

  foreach my $file ( @$files ) {
    my ( $from, $to ) = each %$file;
    keys %$file; # explicitly reset "each" iterator

    my $zip_filename = $self->_rename_file($to);

    # trim off the leading slash
    ( my $trimmed_zip_filename = $zip_filename ) =~ s|^/||;

    # this might not be strictly necessary, but there were some strange things
    # going on while testing this operation: stringify the filenames, to avoid
    # the Path::Class::File object going into the zip archive
    $zip->addFile($from, $trimmed_zip_filename);

    $pb++;
  }

  # add the stats file, if there is one
  if ( $stats_file ) {
    my $renamed_stats_file = file( $self->_renamed_id, 'stats.csv');
    $zip->addFile($stats_file->stringify, $renamed_stats_file);
  }

  return $zip;
}

#-------------------------------------------------------------------------------

# gzips the supplied data and returns the compressed data

sub _compress_data {
  my ( $self, $data ) = @_;

  my $max        = length $data;
  my $num_chunks = 100;
  my $chunk_size = int( $max / $num_chunks ) +1;

  # set up the progress bar
  my $pb = $self->_create_pb('gzipping', $num_chunks);

  my $compressed_data;
  my $offset      = 0;
  my $remaining   = $max;
  my $z           = IO::Compress::Gzip->new( \$compressed_data );
  while ( $remaining > 0 ) {
    # write the data in chunks
    my $chunk = ( $chunk_size > $remaining )
              ? substr $data, $offset
              : substr $data, $offset, $chunk_size;

    $z->print($chunk);

    $offset    += $chunk_size;
    $remaining -= $chunk_size;
    $pb++;
  }

  $z->close;

  return $compressed_data;
}

#-------------------------------------------------------------------------------

# writes the supplied data to the specified file. This method doesn't care what
# form the data take, it just dumps the raw data to file, showing a progress
# bar if required.

sub _write_data {
  my ( $self, $data, $filename ) = @_;

  if ( -e $filename and not $self->force ) {
    Bio::Path::Find::Exception->throw(
      msg => qq(ERROR: output file "$filename" already exists; not overwriting. Use "-F" to force overwriting)
    );
  }

  my $max        = length $data;
  my $num_chunks = 100;
  my $chunk_size = int( $max / $num_chunks ) + 1;

  my $pb = $self->_create_pb('writing', $num_chunks);

  open ( FILE, '>', $filename )
    or Bio::Path::Find::Exception->throw( msg => "ERROR: couldn't write output file ($filename): $!" );

  binmode FILE;

  my $written;
  my $offset      = 0;
  my $remaining   = $max;
  my $cycle = 0;
  while ( $remaining > 0 ) {
    $written = syswrite FILE, $data, $chunk_size, $offset;
    $offset    += $written;
    $remaining -= $written;
    $pb++;
    $cycle++;
  }

  close FILE;
}

#-------------------------------------------------------------------------------

1;
