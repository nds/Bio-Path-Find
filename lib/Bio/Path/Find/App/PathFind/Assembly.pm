
package Bio::Path::Find::App::PathFind::Assembly;

# ABSTRACT: find assemblies

use v5.10; # for "say"

use MooseX::App::Command;
use namespace::autoclean;
use MooseX::StrictConstructor;

use Path::Class;

use Bio::Path::Find::Types qw( :types );

use Bio::Path::Find::Lane::Class::Assembly;
use Bio::Path::Find::Exception;

extends 'Bio::Path::Find::App::PathFind';

with 'Bio::Path::Find::Role::Linker',
     'Bio::Path::Find::Role::Archivist',
     'Bio::Path::Find::Role::Statistician';

#-------------------------------------------------------------------------------
#- usage text ------------------------------------------------------------------
#-------------------------------------------------------------------------------

# this is used when the "pf" app class builds the list of available commands
command_short_description 'Find genome assemblies';

=head1 NAME

pf assemblies - Find genome assemblies

=head1 USAGE

  pf assembly --id <id> --type <ID type> [options]

=head1 DESCRIPTION

The C<assembly> command finds genome assemblies. If a lane's reads have been
assembled using more than one assembly pipeline, e.g. C<iva> and C<spades>,
data for all assemblies are reported by default.

Search for assemblies by specifying the type of data, using the C<--type>
option (C<lane>, C<sample>, etc), and the ID, using the C<--id> option.

=head1 EXAMPLES

  # get paths for scaffolds for a set of lanes
  pf assembly -t lane -i 12345_1
  pf assembly -t lane -i 12345_1 -f scaffold

  # get contigs for a set of lanes
  pf assembly -t lane -i 12345_1 -f contigs

  # get both contigs and scaffold for a set of lanes
  pf assembly -t lane -i 12345_1 -f all

  # get scaffolds for only IVA assemblies
  pf assembly -t lane -i 12345_1 -P iva

  # write statistics for the assemblies to a CSV file
  pf assembly -t lane -i 12345_1 -s my_assembly_stats.csv

  # archive contigs in a gzip-compressed tar file
  pf assembly -t lane -i 10018_1 -a my_contigs.tar.gz

=head1 OPTIONS

These are the options that are specific to C<pf assembly>. Run C<pf man> to see
information about the options that are common to all C<pf> commands.

=over

=item --program, -P <assembler>

Restrict search to files generated by one of the specified assemblers. You
can give multiple assemblers by adding C<-P> multiple times

  pf assembly -t lane -i 12345 -P iva -P spades

or by giving it a comma-separated list of assembler names:

  pf assembly -t lane -i 12345 -P iva,spades

The assembler must be one of C<iva>, C<pacbio>, C<spades>, or C<velvet>.
Default: return files from all assembly pipelines.

=item --filetype, -f <filetype>

Type of assembly files to find. Either C<scaffold> (default) or C<contigs>.

=item --stats, -s [<stats filename>]

Write a file with statistics about found lanes. Save to specified filename,
if given. Default filename: <ID>_assemblyfind_stats.csv

=item --symlink, -l [<symlink directory>]

Create symlinks to found data. Create links in the specified directory, if
given, or in the current working directory by default.

=item --archive, -a [<tar filename>]

Create a tar archive containing data files for found lanes. Save to specified
filename, if given. Default filename: assemblyfind_<ID>.tar.gz

=item --no-tar-compression, -u

Don't compress tar archives.

=item --zip, -z [<zip filename>]

Create a zip archive containing data files for found lanes. Save to specified
filename, if given. Default filename: assemblyfind_<ID>.zip

=item --rename, -r

Rename filenames when creating archives or symlinks, replacing hashed (#)
with underscores (_).

=back

=head1 SCENARIOS

=head2 Find assemblies

The C<pf assembly> command finds and prints the locations of scaffolds by
default:

  % pf assembly -t lane -i 5008_5#1

You can also find contigs for an assembly:

  % pf assembly -t lane -i 5008_5#1 -f contigs

If you want to see both scaffolds and contigs for each assembly:

  % pf assembly -t lane -i 5008_5#1 -f all

=head2 Find assemblies from a particular pipeline

If reads from a given lane have been assembled by multiple assemblies, for
example by both IVA and SPAdes, the default behaviour is to return either
contigs or scaffolds from both assemblies. If you are interested in the
results of a particular assembler, you can specify it using the C<--program>
options:

  % pf assembly -t lane -i 5008_5#1 --program iva

=head2 Get statistics for an assembly

You can generate a file with the statistics for an assembly using the
C<--stats> option:

  % pf assembly -t lane -i 5008_5#1 --stats

You can specify the name of the stats file by adding to the C<-s> option:

  % pf assembly -t lane -i 5008_5#1 -s my_assembly_stats.csv

You can also write the statistics as a more readable tab-separated file:

  pf accession -t lane -i 10018_1 -o -c "<tab>"

(To enter a tab character you might need to press ctrl-V followed by tab.)

=cut

#-------------------------------------------------------------------------------
#- command line options --------------------------------------------------------
#-------------------------------------------------------------------------------

option 'filetype' => (
  documentation => 'type of files to find',
  is            => 'ro',
  isa           => AssemblyType,
  cmd_aliases   => 'f',
  default       => 'scaffold',
);

#---------------------------------------

option 'program' => (
  documentation => 'look for assemblies created by a specific assembler',
  is            => 'ro',
  isa           => Assemblers,
  cmd_aliases   => 'P',
  cmd_split     => qr/,/,
);

#-------------------------------------------------------------------------------
#- private attributes ----------------------------------------------------------
#-------------------------------------------------------------------------------

# this is a builder for the "_lane_class" attribute that's defined on the parent
# class, B::P::F::A::PathFind. The return value specifies the class of lane
# objects that should be returned by the Finder.

sub _build_lane_class {
  return 'Bio::Path::Find::Lane::Class::Assembly';
}

#---------------------------------------

# this is a builder for the "_stats_file" attribute that's defined by the
# B::P::F::Role::Statistician. This attribute provides the default name of the
# stats file that the command writes out

sub _stats_file_builder {
  my $self = shift;
  return file( $self->_renamed_id . '.assemblyfind_stats.csv' );
}

#---------------------------------------

# set the default name for the symlink directory

around '_build_symlink_dir' => sub {
  my $orig = shift;
  my $self = shift;

  my $dir = $self->$orig->stringify;
  $dir =~ s/^pf_/assemblyfind_/;

  return dir( $dir );
};

#---------------------------------------

# set the default names for the tar or zip files

around [ '_build_tar_filename', '_build_zip_filename' ] => sub {
  my $orig = shift;
  my $self = shift;

  my $filename = $self->$orig->stringify;
  $filename =~ s/^pf_/assemblyfind_/;

  return file( $filename );
};

#-------------------------------------------------------------------------------
#- public methods --------------------------------------------------------------
#-------------------------------------------------------------------------------

sub run {
  my $self = shift;

  # fail fast if we're going to end up overwriting a file later on
  if ( not $self->force ) {

    # writing stats
    if ( $self->_stats_flag and -f $self->_stats_file ) {
      Bio::Path::Find::Exception->throw(
        msg => q(ERROR: output file ") . $self->_stats_file . q(" already exists; not overwriting existing file. Use "-F" t- force overwriting)
      );
    }

    # writing archives
    if ( $self->_tar_flag and -f $self->_tar ) {
      Bio::Path::Find::Exception->throw(
        msg => q(ERROR: output file ") . $self->_tar . q(" already exists; not overwriting existing file. Use "-F" t- force overwriting)
      );
    }
    if ( $self->_zip_flag and -f $self->_zip ) {
      Bio::Path::Find::Exception->throw(
        msg => q(ERROR: output file ") . $self->_zip . q(" already exists; not overwriting existing file. Use "-F" t- force overwriting)
      );
    }

  }

  # set up the finder

  # build the parameters for the finder
  my %finder_params = (
    ids      => $self->_ids,
    type     => $self->_type,
    filetype => $self->filetype,    # defaults to "scaffold"
  );

  # should we restrict the search to a specific assembler ?
  if ( $self->program ) {
    $self->log->debug( 'finding lanes with assemblies created by ' . $self->program );

    # yes; tell the Finder to set the "assemblers" attribute on every Lane that
    # it returns
    $finder_params{lane_attributes}->{assemblers} = $self->program;
  }

  # find lanes
  my $lanes = $self->_finder->find_lanes(%finder_params);

  $self->log->debug( 'found a total of ' . scalar @$lanes . ' lanes' );

  if ( scalar @$lanes < 1 ) {
    say STDERR 'No data found.';
    exit;
  }

  # do something with the found lanes
  if ( $self->_symlink_flag or
       $self->_tar_flag or
       $self->_zip_flag or
       $self->_stats_flag ) {
    $self->_make_symlinks($lanes) if $self->_symlink_flag;
    $self->_make_tar($lanes)      if $self->_tar_flag;
    $self->_make_zip($lanes)      if $self->_zip_flag;
    $self->_make_stats($lanes)    if $self->_stats_flag;
  }
  else {
    # we've set a default ("scaffold") for the "filetype" on the Finder, so
    # when it looks for lanes it will automatically tell each lane to find
    # files of type "scaffold". Hence, "print_paths" will print the paths for
    # those found files.
    $_->print_paths for ( @$lanes );
  }

}

#-------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;

1;

