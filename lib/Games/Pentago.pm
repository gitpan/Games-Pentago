package Games::Pentago;

use warnings;
use strict;
use Carp;
use POSIX qw/ceil/;
use Exporter qw/import/;

use constant {
	DIR_NONE => 0,	# this is not a legal move
	DIR_CW   => 1,
	DIR_CCW  => 2,

	REFL_PRED  => 0,
	REFL_TRANS => 1,

	DISP_NO_AXES   => 1,
	DISP_NO_SPACES   => 2,
	DISP_NO_NEWLINES => 4,
};

our @EXPORT_OK = qw/
	DIR_CW DIR_CCW
	DISP_NO_AXES DISP_NO_SPACES DISP_NO_NEWLINES
/;
our %EXPORT_TAGS = (
	directions => ['DIR_CW','DIR_CCW'],
	disp_flags => ['DISP_NO_AXES','DISP_NO_SPACES','DISP_NO_NEWLINES']
);

=head1 NAME

Games::Pentago - Represent and play Pentago games and its variants.

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    # Using the gameplay loop
    use Games::Pentago;
    my $pentago = Games::Pentago->new;
    $pentago->play;
    
    # A 4-player variant
    my $pentagoXL = Games::Pentago->new(
         board_size => 3,
         players    => ['X','O','#','%']
    );
    $pentagoXL->play;


=head1 DESCRIPTION

Pentago is a two-player abstract strategy game invented by Tomas Flodén. The 
game is played on a 6×6 board divided into four 3×3 sub-boards (or quadrants). 
Taking turns, the two players place a marble of their color onto an unoccupied 
space on the board, and then rotate one of the sub-boards by 90 degrees either 
clockwise or counter-clockwise. A player wins by getting five of their marbles 
in a vertical, horizontal or diagonal row. If all 36 spaces on the board are 
occupied without a row of five being formed then the game is a draw.

A Games::Pentago object represents a game of Pentago or a variant.

For specifying direction, use the constants C<Games::Pentago::CW> and 
C<Games::Pentago::CCW>.
Sub-boards are enumerated with integers starting at 0 in the upper-left corner.

=head1 METHODS

=head2 Construction

=over 4

=item new()

Constructs a new Pentago game. If you want a variant of Pentago, you can change 
the default values by passing arguments on the form (key,value). Possible keys
are:

  sub_board_size     Side length of a sub-board (default 3).
  board_size         Number of sub-boards on one side (default 2).
  row_length         Number of marbles in a row required to win (default 5).
  players            Reference to an array of the players' symbols.
  empty_symbol       Symbol for empty squares (default '.').

=cut

sub new {
	my $class = shift;

	# Settings
	my %defaults = (
		board_size => 2, # Side length of board in sub-boards
		sub_board_size => 3, # Side length of sub-boards in squares
		row_length => 5, # Number of marbles in a row required to win
		players => ['X','O'],
		empty_symbol => '.',
		player => 0,
	);
	my %opt = @_;
	for my $key ( keys %defaults ) {
		$opt{$key} = $defaults{$key} unless defined $opt{$key};
	}
	for my $key ( qw/board_size sub_board_size row_length/ ) {
		croak "invalid $key" unless $opt{$key} =~ m/^\d+$/;
	}
	for my $symb ( @{$opt{'players'}} ) {
		croak "symbol $symb doesn't fit" unless length $symb == 1;
	}
	
	my $self = \%opt;
	bless $self, $class;
	$$self{'squares_per_side'} = $$self{'board_size'}*$$self{'sub_board_size'};
	$$self{'symbols'} = [@{$$self{'players'}}, $$self{'empty_symbol'}];
	$$self{'empty_id'} = scalar @{$$self{'players'}};
	$$self{'square_size'} = ceil( log( @{$$self{'symbols'}} ) / log(2) );
	$$self{'square_size'} = 2**ceil( log($$self{'square_size'}) / log(2) );
	carp "probably too many players" if $$self{'square_size'} > 32;
	$$self{'board'} = '';
	$$self{'lines'} = $self->_lines();
	$self->_empty_board();
	return $self;
}

sub _lines {
	my $self = shift;
	my @lines = ();
	for my $x ( -$$self{'squares_per_side'}+1..$$self{'squares_per_side'}-1 ) {
		my ( @line, @diagR, @diagL );
		for my $y ( 0..$$self{'squares_per_side'}-1 ) {
			push @line, [$x,$y] if $self->valid_square($x,$y);
			push @diagR, [$x+$y,$y] if $self->valid_square($x+$y,$y);
			push @diagL, [$x-$y,$y] if $self->valid_square($x-$y,$y);
		}
		push @lines, \@line;
		push @lines, \@diagR if @diagR >= $$self{'row_length'};
		push @lines, \@diagL if @diagL >= $$self{'row_length'};
	}
	for my $y ( 0..$$self{'squares_per_side'}-1 ) {
		my @line = ();
		for my $x ( 0..$$self{'squares_per_side'}-1 ) {
			push @line, [$x,$y];
		}
		push @lines, \@line;
	}
	return \@lines;
}

sub _empty_board {
	my $self = shift;
	for my $x ( 0..$$self{'board_size'}*$$self{'sub_board_size'}-1 ) {
		for my $y ( 0..$$self{'board_size'}*$$self{'sub_board_size'}-1 ) {
			$self->_set_int( $x, $y, $$self{'empty_id'} );
		}
	}
}

=back

=head2 Object methods

=over 4

=item move()

Makes a move, i.e. puts a marble belonging to the current player, rotates a 
sub-board and makes the next player the current player. Takes four arguments: 
the X and Y coordinates, subboard and direction.

=cut

sub move {
	croak "not enough arguments for move()" if @_ != 5;
	my ( $self, $x, $y, $subboard, $direction ) = @_;
	if ( $self->empty($x,$y) ) {
		$self->_set_int( $x, $y, $$self{'player'} );
		$self->rotate( $subboard, $direction );
		$self->next_player();
	} else {
		carp "square ($x,$y) is not empty!";
	}
}

=item rotate()

Rotates a sub-board. Takes the sub-board and the direction
(C<Games::Pentago::CW> or C<Games::Pentago::CCW>) as arguments.

=cut

sub rotate {
	# this could be optimized
	my ( $self, $subboard, $direction ) = @_;
	croak "invalid sub-board" unless defined $subboard
		&& $subboard =~ m/^\d+$/ && $subboard < $$self{'board_size'}**2;
	carp "no direction given" unless defined $direction;
	if ( $direction == DIR_NONE ) {
		return;
	} elsif ( $direction == DIR_CW ) {
		$self->rotate( $subboard, DIR_CCW ) for ( 1..3);
		return;
	}
	my $cx = $$self{'sub_board_size'}
		* ( $subboard % $$self{'board_size'} + 1/2 ) - 1/2;
	my $cy = $$self{'sub_board_size'}
		* ( int( $subboard / $$self{'board_size'} ) + 1/2 ) - 1/2;
	my @difs = ();
	for (
		my $d = -($$self{'sub_board_size'}-1)/2;
		@difs < $$self{'sub_board_size'}; $d++
	) { push @difs, $d; }
	my @refls = (
		{	# along y=0
			REFL_PRED => sub { return $_[1] > 0 },
			REFL_TRANS => sub { return ( $_[0], -$_[1] ) }
		},
		{	# along y=x
			REFL_PRED => sub { return $_[1] + $_[0] < 0 },
			REFL_TRANS => sub { return ( -$_[1], -$_[0] ) }
		},
	);
	for my $refl ( @refls ) {
		for my $dy ( @difs ) {
			for my $dx ( @difs ) {
				if ( &{$$refl{REFL_PRED}}($dx,$dy) ) {
					my ( $newdx, $newdy ) = &{$$refl{REFL_TRANS}}($dx,$dy);
					$self->_swap( $cx+$dx, $cy+$dy, $cx+$newdx, $cy+$newdy );
				}
			}
		}
	}
}

sub _swap {
	my ( $self, $x0, $y0, $x1, $y1 ) = @_;
	my $v0 = $self->_at_int($x0,$y0);
	my $v1 = $self->_at_int($x1,$y1);
	$self->_set_int($x0,$y0,$v1);
	$self->_set_int($x1,$y1,$v0);
	return;
}

=item next_player()

Makes the next player the current player. Takes no arguments.

=cut

sub next_player {
	my $self = shift;
	$$self{'player'} = ( $$self{'player'} + 1 ) % @{$$self{'players'}};
}

=item player()

Returns the symbol of the current player. Takes no arguments.

=cut

sub player {
	my $self = shift;
	${$$self{'symbols'}}[$$self{'player'}];
}

=item valid_square()

Returns true if the given square is on the board. Takes X and Y as arguments.

=cut

sub valid_square {
	my $self = shift;
	return 0 <= $_[0] && $_[0] < $$self{'squares_per_side'}
		&& 0 <= $_[1] && $_[1] < $$self{'squares_per_side'}
}

=item at()

Returns the symbol at a square. Takes X and Y as arguments.

=cut

*at = \&_at_str;
sub _at_str {
	my ( $self, $x, $y ) = @_;
	return $$self{'symbols'}[ $self->_at_int($x,$y) ];
}
sub _at_int {
	my ( $self, $x, $y ) = @_;
	vec(
		$$self{'board'},
		$x + $y * $$self{'board_size'} * $$self{'sub_board_size'},
		$$self{'square_size'}
	);
}

=item empty()

Returns true if a square is empty. Takes X and Y as arguments.

=cut

sub empty {
	my ( $self, $x, $y ) = @_;
	return ( $self->_at_int($x,$y) == $$self{'empty_id'} );
}

=item set()

Puts a symbol on an a square. Takes X, Y and the symbol as arguments. The 
symbol must correspond to a player.

=cut

*set = \&_set_str;
sub _set_str {
	my ( $self, $x, $y, $symbol ) = @_;
	my $num_symbs = $#{$$self{'symbols'}};
	for my $i ( 0..$num_symbs ) {
		if ( ${$$self{'symbols'}}[$i] eq $symbol ) {
			$self->_set_int( $x, $y, $i );
			return;
		}
	}
	carp "symbol not found: $symbol";
}
sub _set_int {
	my ( $self, $x, $y, $value ) = @_;
	printf "vec(%s,%d,%d)\n",
		'-',
		$x + $y * $$self{'board_size'} * $$self{'sub_board_size'},
		$$self{'square_size'};
	vec(
		$$self{'board'},
		$x + $y * $$self{'board_size'} * $$self{'sub_board_size'},
		$$self{'square_size'}
	) = $value;
}

=item str()

Returns a string describing the game position. Optionally takes a combination 
of flags as an argument.

  DISP_NO_AXES     Do not write the axes and borders.
  DISP_NO_SPACES   Do not put spaces between columns.
  DISP_NO_NEWLINES Remove all newlines.

Sample output, without flags:

           0 1 2 3 4 5 
         +------------
	0| . . . . X .
	1| . . O O . .
	2| . . X . . .
	3| . O . . . .
	4| X . O . . .
	5| . X . . . .


=cut

sub str {
	my ( $self, $flags ) = ( @_, 0 );
	my $str = '';
	unless ( $flags & DISP_NO_AXES ) {
		$str .= ' ' x length($$self{'squares_per_side'}-1) . '  ';
		$str .= sprintf '%-2d', $_ for ( 0..$$self{'squares_per_side'}-1 );
		$str .= "\n";
		$str .= ' ' x length($$self{'squares_per_side'}-1);
		$str .= '+';
		$str .= '-' x (2*$$self{'squares_per_side'});
		$str .= "\n";
	}
	for my $y ( 0..$$self{'board_size'}*$$self{'sub_board_size'}-1 ) {
		$str .= sprintf '%-'.length($$self{'squares_per_side'}-1).'d|', $y
			unless $flags & DISP_NO_AXES;
		for my $x ( 0..$$self{'board_size'}*$$self{'sub_board_size'}-1 ) {
			$str .= ' ' unless $flags & DISP_NO_SPACES;
			$str .= $self->_at_str( $x, $y );
		}
		$str .="\n" unless $flags& DISP_NO_NEWLINES && $flags& DISP_NO_AXES;
	}
	return $str;
}

=item print()

Prints the output of C<str>. Takes the same flags as C<str>.

=cut

sub print {
	my ( $self, $flags ) = ( @_, 0 );
	print $self->str( $flags );
}

=item winners()

Returns a list of the players who have the required number of marbles in a row.

=cut

sub winners {
	my $self = shift;
	my %winner = ();
	for my $line ( @{$$self{'lines'}} ) {
		my ( $searching, $consecutive ) = (0,0);
		for my $point ( @$line ) {
			my $here = $self->_at_int( @$point );
			if ( $searching == $here && $here != $$self{'empty_id'} ) {
				$consecutive++;
				$winner{$searching} = 1 if $consecutive >= $$self{'row_length'};
			} else {
				$consecutive = 1;
				$searching = $here;
			}
		}
	}
	return map {+ $$self{'players'}[$_]} keys %winner;
}

=item play()

Enters a play loop that reads from standard input and lets you play the game.

=cut

sub play {
	my $self = shift;
	$self->print;
	print $self->player, ': ';
	while ( <> ) {
		chomp;
		my @move = ( length == 4 ? split // : split /[ ,]+/ );
		if ( @move == 4 ) {
			$move[3] = ( $move[3] eq 'a' ? DIR_CCW : DIR_CW );
			$self->move( @move );
			$self->print;
			last if ( $self->winners > 0 );
			print $self->player, ': ';
		} else {
			print "format: x,y,subboard,direction\n",
			      "  direction is 'a' for anticlockwise or 'c' for clockwise\n",
				  "  x, y and subboard are positive integers\n",
				  "e.g: 0,0,3,a or 003a";
		}
	}
}

=back

=head1 AUTHOR

Tim Nordenfur, C<< <tim at gurka.se> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-games-pentago at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Games-Pentago>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Games::Pentago


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Games-Pentago>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Games-Pentago>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Games-Pentago>

=item * Search CPAN

L<http://search.cpan.org/dist/Games-Pentago/>

=back


=head1 ACKNOWLEDGEMENTS

Pentago was found by Tomas Flodén.

Parts of the introducing text were taken from the Wikipedia article on Pentago.

=head1 LICENSE AND COPYRIGHT

Copyright 2010 Tim Nordenfur.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Games::Pentago
