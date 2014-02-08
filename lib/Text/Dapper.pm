package Text::Dapper;

use utf8;
use open ':std', ':encoding(UTF-8)';
use 5.006;
use strict;
use warnings FATAL => 'all';

use vars '$VERSION';

use IO::Dir;
use Template::Liquid;

use Text::MultiMarkdown 'markdown';
use HTTP::Server::Brick;
use YAML::Tiny qw(LoadFile Load Dump);
use File::Spec::Functions qw/ canonpath /;
use File::Path qw(make_path);

use Data::Dumper;
#$Data::Dumper::Indent = 1;
#$Data::Dumper::Sortkeys = 1;

use DateTime;

use Text::Dapper::Init;
use Text::Dapper::Utils;
use Text::Dapper::Defaults;
use Text::Dapper::Filters;

my $DEFAULT_PORT   = 8000;

=head1 NAME

Text::Dapper - A static site generator

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Text::Dapper;

    my $foo = Text::Dapper->new();
    ...

State Machine

=over 4

=item S1. Initialize. When a Dapper object is initialized, it reads its default config.

=item T1. Init-configure transition

=item S2. Configure. Read project-specific configuration file.

=item T2. configure-parse transition

=item S3. Parse. Calls markdown for content by default.

=item T3. Parse-render transition

=item S4. Render. Calls Liquid by default. Custom plugins can be written.

=item T4. Render-cleanup transition

=item S5. Cleanup

=back

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=cut

use Exporter qw(import);

our @EXPORT = qw($VERSION);

=head1 SUBROUTINES/METHODS

=head2 function1

=cut

sub new {
    my $class = shift;
    my $self = {
        created=> 1,
        source => shift,
        output => shift,
        layout => shift,
        config => shift,
    };

    $self->{site} = Text::Dapper::Defaults::get_defaults();
    $self->{site}->{time} = DateTime->now( time_zone => DateTime::TimeZone->new( name => 'local' ) );
    $self->{source} = "_source" unless defined($self->{source});
    $self->{output} = "_output" unless defined($self->{output});
    $self->{layout} = "_layout" unless defined($self->{layout});
    $self->{config} = "_config" unless defined($self->{config});

    bless $self, $class;
    return $self;
}

=head2 function2

=cut

sub init {
    my ($self) = @_;

    Text::Dapper::Init::init();

    print "Project initialized.\n";
}

sub build {
    my($self) = @_;
    
    $self->parse();
    $self->transform();
    $self->render();

    print "Project built.\n";
}

sub parse {
    my ($self) = @_;

    # load program and project configuration
    $self->read_project();

    # replaces the values of h_template with actual content
    $self->read_templates();
}

sub transform {
    my ($self) = @_;

    # recurse through the project tree and generate output (combine src with templates)
    $self->walk($self->{source}, $self->{output});
}

sub render {
    my ($self) = @_;

    for my $page (@{$self->{site}->{pages}}) {

        #print Dump $page->{content};

        if (not $page->{layout}) { $page->{layout} = "index"; }
        my $layout = $self->{layout_content}->{$page->{layout}};
        
        # Make sure we have a copy of the template file
        my $parsed_template = Template::Liquid->parse($layout);

        my %tags = ();
        $tags{site} = $self->{site};
        $tags{page} = $page;
        #$tags{page}->{content} = $content;

        # Render the output file using the template and the source
        my $destination = $parsed_template->render(%tags);

        # Parse and render once more to make sure that any liquid statments
        # In the source file also gets rendered
        $parsed_template = Template::Liquid->parse($destination);
        $destination = $parsed_template->render(%tags);

        if ($page->{filename}) {
            make_path($page->{dirname}, { verbose => 1 });
            open(DESTINATION, ">$page->{filename}") or die "error: could not open destination file:$page->{filename}: $!\n";
            print(DESTINATION $destination) or die "error: could not print to $page->{filename}: $!\n";
            close(DESTINATION) or die "error: could not close $page->{filename}: $!\n";

            print "Wrote $page->{filename}\n";
            #print Dumper $page;
        }
        else {
            print Dumper "No filename specified\n";
        }
    }

    #print Dumper $self->{site};

    #print Dumper($self->{site}); 
    # copy additional files and directories
    $self->copy(".", $self->{output});
}

sub serve {
    my($self, $port) = @_;

    $port = $DEFAULT_PORT unless $port;

    my $s = HTTP::Server::Brick->new(port=>$port);
    $s->add_type('text/html' => qw(^[^\.]+$));
    $s->mount("/"=>{ path=>"_output" });
    #handler => sub { my ($req, $res) = @_; print $req; $res->header('Content-type', 'text/html'); 1; }, #wildcard => 1,

    $s->start
}

# read_project reads the project file and places the values found
# into the appropriate hash.
sub read_project {
    my ($self) = @_;

    my $config = LoadFile($self->{config}) or die "error: could not load \"$self->{config}\": $!\n";

    # Graft together
    #@hash1{keys %hash2} = values %hash2;
    @{$self->{site}}{keys %$config} = values %$config;

    die "error: \"source\" must be defined in project file\n" unless defined $self->{source};
    die "error: \"output\" must be defined in project file\n" unless defined $self->{output};
    die "error: \"layout\" must be defined in project file\n" unless defined $self->{layout};

    #print Dump($self->{site});
}

# read_templates reads the content of the templates specified in the project configuration file.
sub read_templates {
    my ($self) = @_;
    my ($key, $ckey);

    opendir(DIR, $self->{layout}) or die $!;
    my @files = sort(grep(!/^(\.|\.\.)$/, readdir(DIR)));

    for my $file (@files) {
        my $stem = Text::Dapper::Utils::filter_stem($file);
        $file = $self->{layout} . "/" . $file;
        $self->{layout_content}->{$stem} = Text::Dapper::Utils::read_file($file);
        #print "$stem layout content:\n";
        #print $self->{layout_content}->{$stem};
    }

    # Expand sub layouts
    for my $key (keys $self->{layout_content}) {
        my $value = $self->{layout_content}->{$key};
        my $frontmatter;
        my $content;

        $value =~ /(---.*?)---(.*)/s;

        if (not defined $1) { next; }
        if (not defined $2) { next; }

        $frontmatter = Load($1);
        $content  = $2;

        if (not defined $frontmatter->{layout}) { next; }
        if (not defined $self->{layout_content}->{$frontmatter->{layout}}) { next; }

        my $master = $self->{layout_content}->{$frontmatter->{layout}};
        $master =~ s/\{\{ *page\.content *\}\}/$content/g;
        $self->{layout_content}->{$key} = $master;

        #print "$key Result:\n" . $self->{layout_content}->{$frontmatter->{layout}} . "\n\n\n\n\n\n";
    }
}

# recursive descent
sub walk {
  my ($self, $source_dir, $output_dir) = @_;
  my $source_handle = new IO::Dir "$source_dir";;
  my $output_handle = new IO::Dir "$output_dir";;
  my $directory_element;

  # if the directory does not exist, create it
  if (!(defined $output_handle)) {
    mkdir($output_dir);
    $output_handle = new IO::Dir "$output_dir";
  }

  if (defined $source_handle) {

    # cycle through each element in the current directory
    while(defined($directory_element = $source_handle->read)) {

      # print "directory element:$source/$directory_element\n";
      if(-d "$source_dir/$directory_element" and $directory_element ne "." and $directory_element ne "..") {
        $self->walk("$source_dir/$directory_element", "$output_dir/$directory_element");
      }
      elsif(-f "$source_dir/$directory_element" and $directory_element ne "." and $directory_element ne "..") {
   
        # Skip dot files
        if ($directory_element =~ /^\./) { next; }
    
        # Construct output file name, which is a combination
        # of the stem of the source file and the extension of the template.
        # Example:
        #   - Source: index.md
        #   - Template: layout.html
        #   - Destination: index.html
        my $source = "$source_dir/$directory_element";
        my $output = "$output_dir/$directory_element";
      
        $self->taj_mahal($source, $output);
      }
    }
    undef $source_handle;
  }
  else {
    die "error: could not get a handle on $source_dir/$directory_element";
  }
  #undef %b_ddm;
}

# Takes a source file and destination file and adds an appropriate meta data entries to the taj mahal multi-tiered site hash.
sub taj_mahal {
    my ($self, $source_file_name, $destination_file_name) = @_;

    my %page = ();

    my $source_content = Text::Dapper::Utils::read_file($source_file_name);

    $source_content =~ /(---.*?)---(.*)/s;

    my ($frontmatter) = Load($1);
    $page{content} = $2;

    for my $key (keys $frontmatter) {
        $page{$key} = $frontmatter->{$key};
    }

    $page{slug} = Text::Dapper::Utils::slugify($page{title});

    if (not $page{date}) {
        my $date = Text::Dapper::Utils::get_modified_time($source_file_name);
        #print "Didn't find date for $source_file_name. Setting to file modified date of $date\n";
        $page{date} = $date;
    }
   
    if($page{date} =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d)\:(\d\d)\:(\d\d)$/) {
        $page{year} = $1;
        $page{month} = $2;
        $page{day} = $3;
        $page{hour} = $4;
        $page{minute} = $5;
        $page{second} = $6;
        $page{nanosecond} = 0;
    }

    if(not $page{timezone}) {
        $page{timezone} = DateTime::TimeZone->new( name => 'local' );
    }

    $page{date} = DateTime->new(
        year       => $page{year},
        month      => $page{month},
        day        => $page{day},
        hour       => $page{hour},
        minute     => $page{minute},
        second     => $page{second},
        nanosecond => $page{nanosecond},
        time_zone  => $page{timezone},
    );

    $page{url} = $self->{site}->{urlpattern};
    $page{url} =~ s/\:category/$page{categories}/g unless not defined $page{categories};
    $page{url} =~ s/\:year/$page{year}/g unless not defined $page{year};
    $page{url} =~ s/\:month/$page{month}/g unless not defined $page{month};
    $page{url} =~ s/\:day/$page{day}/g unless not defined $page{day};
    $page{url} =~ s/\:slug/$page{slug}/g unless not defined $page{slug};

    $page{id} = $page{url};

    if (not defined $page{extension}) { $page{extension} = ".html"; }

    $page{source_file_extension} = Text::Dapper::Utils::filter_extension($source_file_name);

    $page{filename} = Text::Dapper::Utils::filter_stem("$destination_file_name") . $page{extension};
    
    #print "FILENAME BEFORE: " . $page{filename} . "\n";
    #print "FILENAME AFTER: " . $page{filename} . "\n";

    if(defined $page{categories}) {
        my $filename = $self->{site}->{output} . $page{url};
        $filename =~ s/\/$/\/index.html/; 
        $page{filename} = canonpath $filename;
    }

    my ($volume, $dirname, $file) = File::Spec->splitpath( $page{filename} );
    $page{dirname} = $dirname;

    if ($page{source_file_extension} eq ".md") { 
        $page{content} = markdown($page{content});

        # Save first paragraph of content as excerpt
        $page{content} =~ /(<p>.*?<\/p>)/s;
        $page{excerpt} = $1;
    }
    else {
        print "Did not run markdown on $page{filename} since the extension was not .md\n";
    }

    # Remove leading spaces and newline
    $page{content} =~ s/^[ \n]*//;
    
    if ($page{categories}) {
        push @{$self->{site}->{categories}->{$page{categories}}}, \%page;
    }

    push @{$self->{site}->{pages}}, \%page;
}

# copy(sourcdir, outputdir)
#
# This subroutine copies all directories and files from
# sourcedir into outputdir as long as they do not match
# what is contained in ignore.
sub copy {
    my ($self, $dir, $output) = @_;

    opendir(DIR, $dir) or die $!;

    DIR: while (my $file = readdir(DIR)) {
        for my $i (@{ $self->{site}->{ignore} }) {
            next DIR if ($file =~ m/$i/);
        }

        $output =~ s/\/$//;
        my $command = "cp -r $file $output";
        print $command . "\n";
        system($command);
    }

    closedir(DIR);
}

=head1 AUTHOR

Mark Benson, C<< <markbenson at vanilladraft.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-text-dapper at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Text-Dapper>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Text::Dapper


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Text-Dapper>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Text-Dapper>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Text-Dapper>

=item * Search CPAN

L<http://search.cpan.org/dist/Text-Dapper/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

The MIT License (MIT)

Copyright (c) 2014 Mark Benson

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

=cut

1; # End of Text::Dapper

