package PubSite::Brewery;
use strict;

use Flickr::API2;
use Geo::Coordinates::OSGB qw( grid_to_ll );
use Geo::Coordinates::OSTN02 qw( OSGB36_to_ETRS89 ETRS89_to_OSGB36 );

use base qw( Class::Accessor );
PubSite::Brewery->mk_accessors( qw( id name addr_num addr_street postcode
    dates_open dates_building closed demolished os_x os_y location_accurate
    former_names former_address website twitter rgl quaffale flickr
    notes sources ) );

=head1 NAME

PubSite::Brewery - Model a single brewery for Ewan's pub site.

=head1 DESCRIPTION

Object modelling a single brewery.

=head1 METHODS

=over

=item B<new>

  my $brewery = PubSite::Brewery->new( ... );

=cut

sub new {
  my ( $class, %args ) = @_;
  my $self = \%args;
  bless $self, $class;
  return $self;
}

=item B<lat_and_long>

Returns an array containing the brewery's latitude and longitude,
calculated from the stored values of os_x and os_y.  If os_x or os_y
is missing, returns undef.

=cut

sub lat_and_long {
  my $self = shift;
  my $x = $self->os_x;
  my $y = $self->os_y;

  if ( !$x || !$y ) {
    return undef;
  }

  ( $x, $y ) = OSGB36_to_ETRS89( $x, $y );
  my ( $lat, $long ) = grid_to_ll($x, $y, "WGS84");
  return ( $lat, $long );
}

=item B<lat>

Returns the brewery's latitude, calculated from the stored values of os_x
and os_y.  If os_x or os_y is missing, returns undef.

=cut

sub lat {
  my $self = shift;
  my ( $lat, $long ) = $self->lat_and_long;
  return $lat;
}

=item B<long>

Returns the brewery's longitude, calculated from the stored values of os_x
and os_y.  If os_x or os_y is missing, returns undef.

=cut

sub long {
  my $self = shift;
  my ( $lat, $long ) = $self->lat_and_long;
  return $long;
}

=item B<not_on_map>

Returns true if and only if either os_x or os_y is missing.

=cut

sub not_on_map {
  my $self = shift;
  if ( $self->os_x && $self->os_y ) {
    return 0;
  }
  return 1;
}

=item B<address>

  my $address = $pub->address;

Returns a nicely-formatted address constructed from addr_num, addr_street,
and postcode.

=cut

sub address {
  my $self = shift;
  my $address = $self->addr_num ? $self->addr_num . " " : "";
  $address .= $self->addr_street . ", " . $self->postcode;
  return $address;
}

=item B<has_links>

  my $boolean = $brewery->has_links;

Returns true if and only if the brewery has at least one associated link, e.g.
RGL, Quaffale, etc.

=cut

sub has_links {
  my $self = shift;
  foreach my $key ( qw( rgl quaffale ) ) {
    if ( $self->{$key} ) {
      return 1;
    }
  }
  return 0;
}

=item B<Other accessors>

You can access any of the things you put in when you called new(), e.g.

  my $notes = $brewery->notes;

=back

=cut

sub TO_JSON {
  my $self = shift;

  return {
    id => $self->id,
    name => $self->name,
    lat => $self->lat,
    long => $self->long,
    not_on_map => $self->not_on_map,
    address => $self->address,
    demolished => $self->demolished,
    closed => $self->closed,
    location_accurate => $self->location_accurate,
    dates_open => $self->dates_open,
    dates_building => $self->dates_building,
    former_names => $self->former_names,
    former_address => $self->former_address,
    website => $self->website,
    twitter => $self->twitter,
    rgl => $self->rgl,
    quaffale => $self->quaffale,
    notes => $self->notes,
    sources => $self->sources,
    flickr => $self->flickr,
    has_links => $self->has_links,
  };
}

1;
