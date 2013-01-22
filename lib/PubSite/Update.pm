package PubSite::Update;
use strict;

use base qw( Class::Accessor );
PubSite::Pub->mk_accessors( qw( date change pubs_affected ) );

=head1 NAME

PubSite::Update - Model a single update for Ewan's pub site.

=head1 DESCRIPTION

Object modelling a single update.

=head1 METHODS

=over

=item B<new>

  my $update = PubSite::Update->new(
    date => "09-Oct-12",
    change => "Added Record",
    pubs_affected => "General Graham (EC1)"
  );

=cut

sub new {
  my ( $class, %args ) = @_;
  my $self = \%args;
  bless $self, $class;
  return $self;
}

=item B<Accessors>

You can access any of the things you put in when you called new(), e.g.

  my $date = $update->date;

=back

=cut

1;
