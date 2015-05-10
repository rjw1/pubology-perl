package PubSite;
use strict;

use HTML::Entities;
use HTML::TokeParser;
use PubSite::Brewery;
use PubSite::Pub;
use PubSite::Update;
use Text::CSV::Simple;
use YAML::XS;

our $errstr;

=head1 NAME

PubSite - Makes Ewan's pub site.

=head1 DESCRIPTION

A set of tools for turning Ewan's CSV files into a website.

=head1 METHODS

=over

=item B<extract_html>

Extracts a given div from a static HTML file.

  my $current_text = PubSite->extract_html(
    file => "/home/kake/index.html",
    div_id => "front_page_text" );

=cut

sub extract_html {
  my ( $class, %args )  = @_;

  open( my $fh, "<", $args{file} ) || return 0;
  my $parser = HTML::TokeParser->new( $fh );

  my $current_text = "";
  while ( my $token = $parser->get_tag( "div" ) ) {
    my $attrs = $token->[1];
    if ( $attrs->{id} eq $args{div_id} ) {
      while ( my $bit = $parser->get_token ) {
        if ( $bit->[0] eq "E" && $bit->[1] eq "div" ) {
          last;
        }
        if ( $bit->[0] eq "S" ) {
          if ( $bit->[1] eq "a" ) {
            my $href = $bit->[2]->{href};
            my $name = $bit->[2]->{name};
            my $class = $bit->[2]->{class};
            my $id = $bit->[2]->{id};
            $current_text .= "<" . $bit->[1]
                           . ( $href  ? " href=\"$href\"" : "" )
                           . ( $name  ? " name=\"$name\"" : "" )
                           . ( $class ? " class=\"$class\"" : "" )
                           . ( $id    ? " id=\"$id\"" : "" )
                           . ">";
          } else {
            $current_text .= "<" . $bit->[1] . ">";
          }
        } elsif ( $bit->[0] eq "E" ) {
          $current_text .= "</" . $bit->[1] . ">";
        } elsif ( $bit->[0] eq "T" ) {
          $current_text .= $bit->[1];
        }
      }
      last;
    }
  }

  $current_text = encode_entities( $current_text );

  # put linebreaks back
  $current_text =~ s/&lt;br&gt;/\r\n/g;

  # Strip leading and trailing whitespace.
  $current_text =~ s/^\s+//;
  $current_text =~ s/\s+$//;

  return $current_text;
}

=item B<parse_updates_info_csv>

Parses a CSV of update info.  Returns an array of PubSite::Update objects
in the same order the CSV was in.

  my @data = PubSite->parse_updates_info_csv ( file => "datafile.csv" );

=cut

sub parse_updates_info_csv {
  my ( $class, %args )  = @_;

  my $csv = $args{file} || die "No datafile supplied";

  my $parser = Text::CSV::Simple->new({ binary => 1 });

  $parser->field_map( qw/date change pubs_affected/ );
  my @data = $parser->read_file( $csv );
  @data = @data[ 1 .. $#data ]; # strip the headings

  my @updates;

  foreach my $datum ( @data ) {
    my $update = PubSite::Update->new( %$datum );
    push @updates, $update;
  }

  return @updates;
}

=item B<parse_breweries_csv>

Parses a CSV of breweries.

  my %data = PubSite->parse_breweries_csv( file => "datafile.csv" );

Returns a hash:

=over

=item breweries - ref to an array of PubSite::Brewery objects;

=item min_lat, max_lat, min_long, max_long - scalars

=back

=cut

sub parse_breweries_csv {
  my ( $class, %args )  = @_;

  my $csv = $args{file} || die "No datafile supplied";

  my $parser = Text::CSV::Simple->new({ binary => 1 });

  $parser->field_map( qw/id name addr_num addr_street postcode dates_open
      dates_building closed demolished os_x os_y location_accurate
      former_names former_address website twitter rgl quaffale flickr notes
      sources/ );
  my @data = $parser->read_file( $csv );
  @data = @data[ 1 .. $#data ]; # strip the headings

  @data = sort { $a->{name} cmp $b->{name} } @data;

  my @breweries;
  my ( $min_lat, $max_lat, $min_long, $max_long );

  foreach my $datum ( @data ) {
    # Sort out the Booleans.
    foreach my $key ( qw( closed demolished location_accurate ) ) {
      if ( $datum->{$key} eq "TRUE" ) {
        $datum->{$key} = 1;
      } else {
        $datum->{$key} = 0;
      }
    }

    # Strip dashes from postcodes.
    $datum->{postcode} =~ s/ ---//;

    my $brewery = PubSite::Brewery->new( %$datum );
    push @breweries, $brewery;

    if ( $brewery->not_on_map ) {
      next;
    }

    my ( $lat, $long ) = $brewery->lat_and_long;

    if ( !defined $min_lat ) {
      $min_lat = $max_lat = $lat;
    } elsif ( $lat < $min_lat ) {
      $min_lat = $lat;
    } elsif ( $lat > $max_lat ) {
      $max_lat = $lat;
    }
    if ( !defined $min_long ) {
      $min_long = $max_long = $long;
    } elsif ( $long < $min_long ) {
      $min_long = $long;
    } elsif ( $long > $max_long ) {
      $max_long = $long;
    }
  }

  return (
           breweries => \@breweries,
           min_lat   => $min_lat,
           max_lat   => $max_lat,
           min_long  => $min_long,
           max_long  => $max_long,
         );
}

=item B<parse_csv>

Parses a CSV of pubs.

  # If you want to check Flickr for photo URLs/heights/widths, you must
  # supply both key and secret.  If one or both is missing then check_flickr
  # will be set to 0.

  my %data = PubSite->parse_csv(
                                 file          => "datafile.csv",
                                 check_flickr  => 1, # or 0
                                 flickr_key    => "mykey",
                                 flickr_secret => "mysecret",
                               );

Returns a hash:

=over

=item pubs - ref to an array of PubSite::Pub objects;

=item min_lat, max_lat, min_long, max_long - scalars

=back

=cut

sub parse_csv {
  my ( $class, %args )  = @_;

  my $csv = $args{file} || die "No datafile supplied";
  my $check_flickr = $args{check_flickr} || 0;
  my $flickr_key = $args{flickr_key};
  my $flickr_secret = $args{flickr_secret};
  if ( !$flickr_key || !$flickr_secret ) {
    $check_flickr = 0;
  }

  my $cache_dir = $args{cache_dir} || "";

  my $parser = Text::CSV::Simple->new({ binary => 1 });

  $parser->field_map( qw/id name closed demolished addr_num addr_street
                         postcode 
                         os_x os_y location_accurate alt_name former_addr date_built date_closed owner website rgl fap_rating fap
                         pubs_galore bite
                         bite_2 qype dead_pubs london_eating time_out_rating
                         time_out other_link other_link_2 other_link_3
                         gbg notes sources references flickr/ );
  my @data = $parser->read_file( $csv );
  @data = @data[ 1 .. $#data ]; # strip the headings

  @data = sort { $a->{name} cmp $b->{name} } @data;

  my @pubs;
  my ( $min_lat, $max_lat, $min_long, $max_long );

  # If we're checking Flickr for photo info, load in any cached data.
  my ( $flickr_api, $flickr_file, %flickr_cache );
  if ( $check_flickr ) {
    die "cache_dir not set in call to parse_datafile" unless $cache_dir;
    unless ( -e $cache_dir || mkdir $cache_dir ) {
      die "Can't create cache directory $cache_dir: $!";
    }

    $flickr_api = Flickr::API2->new({ key    => $flickr_key,
                                      secret => $flickr_secret });

    $flickr_file = File::Spec->catfile( $cache_dir, "flickr_data.yaml" );
    if ( -e $flickr_file ) {
      %flickr_cache = YAML::XS::LoadFile( $flickr_file );
    }
  }

  foreach my $datum ( @data ) {
    # Sort out the Booleans.
    foreach my $key ( qw( closed demolished location_accurate ) ) {
      if ( $datum->{$key} eq "TRUE" ) {
        $datum->{$key} = 1;
      } else {
        $datum->{$key} = 0;
      }
    }

    # Strip dashes from postcodes.
    $datum->{postcode} =~ s/ ---//;

    # Get Flickr data if appropriate.
    if ( $check_flickr && $datum->{flickr} ) {
      my @data_needed = qw( photo_url photo_width photo_height photo_date );
      my $photo_url = $datum->{flickr};

      my ( $user_id, $photo_id ) =
                          $photo_url =~ m{flickr.com/photos/([\d\@N]+)/(\d+)};

      # If we have cached data for this photo ID, just use that.
      my $cached_data = $flickr_cache{$photo_id};
      my $got_data = 0;
      if ( $cached_data ) {
        foreach my $key ( @data_needed ) {
          if ( $cached_data->{$key} ) {
            $datum->{$key} = $cached_data->{$key};
            $got_data++;
          }
        }
      }

      if ( $got_data == scalar @data_needed ) {
        # OK, got it all.
      } else {
        # We don't have all the cached data, so go and talk to Flickr.

        my $flickr_api = Flickr::API2->new({
                           key    => $flickr_key,
                           secret => $flickr_secret,
                         });

        # Get the right size.
        my $size_data = $flickr_api->execute_method(
                        "flickr.photos.getSizes", { photo_id => $photo_id } );
        my @images = @{ $size_data->{sizes}{size} };

        foreach my $image ( @images ) {
          if ( $image->{label} eq "Medium" ) {
            $datum->{photo_url} = $image->{source};
            $datum->{photo_width} = $image->{width};
            $datum->{photo_height} = $image->{height};
            last;
          }
        }

        # Get the creation date.
        my $exif_data = $flickr_api->execute_method(
                        "flickr.photos.getExif", { photo_id => $photo_id } );
        my @tags = @{ $exif_data->{photo}{exif} };
        foreach my $tag ( @tags ) {
          if ( $tag->{label} eq "Date and Time (Digitized)" ) {
            my ( $date, $time ) = split( /\s+/, $tag->{raw}{_content} );
            my ( $year, $month, $day ) = split( ":", $date );
            my @months = qw( January February March April May June July August
                             September October November December );
            $datum->{photo_date} = $months[$month - 1] . " " . $year;
            last;
          }
        }

        # OK, we got the data from Flickr - now cache it.
        my $cached_data = {};
        $flickr_cache{$photo_id} = $cached_data;
        foreach my $key ( @data_needed ) {
          $cached_data->{$key} = $datum->{$key};
        }
        $flickr_cache{$photo_id} = $cached_data;
      }
    }

    my $pub = PubSite::Pub->new( %$datum );
    push @pubs, $pub;

    if ( $pub->not_on_map ) {
      next;
    }

    my ( $lat, $long ) = $pub->lat_and_long;

    if ( !defined $min_lat ) {
      $min_lat = $max_lat = $lat;
    } elsif ( $lat < $min_lat ) {
      $min_lat = $lat;
    } elsif ( $lat > $max_lat ) {
      $max_lat = $lat;
    }
    if ( !defined $min_long ) {
      $min_long = $max_long = $long;
    } elsif ( $long < $min_long ) {
      $min_long = $long;
    } elsif ( $long > $max_long ) {
      $max_long = $long;
    }
  }

  # Write out any cached Flickr data.
  if ( $flickr_file ) {
    YAML::XS::DumpFile( $flickr_file, %flickr_cache );
  }

  return (
           pubs => \@pubs,
           min_lat => $min_lat,
           max_lat => $max_lat,
           min_long => $min_long,
           max_long => $max_long,
         );
}

=item B<parse_postal_district_config>

  my %district_conf = PubSite->parse_postal_district_config(
    file => "/export/home/pubology/postal_districts.conf",
  );

If there's an error, then the return value will be false and $PubSite::errstr
will be set.

=cut

sub parse_postal_district_config {
  my $class = shift;
  my %args = @_;

  if ( !$args{file} ) {
    $errstr = "No file supplied to parse_postal_district_config().";
    return 0;
  }

  my $postal_config = Config::Tiny->read( $args{file} );

  if ( !$postal_config ) {
    $errstr = "Can't read postal district config file: "
              . $Config::Tiny::errstr . " (please report this as a bug).";
    return 0;
  }

  return $postal_config;
}

=back

=cut

1;
