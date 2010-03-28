package Data::Google::Visualization::DataTable;

use strict;
use warnings;

use Carp qw(croak carp);
use Storable qw(dclone);
use JSON::XS;
use Time::Local;

our $VERSION = '0.03';

=head1 NAME

Data::Google::Visualization::DataTable - Easily create Google DataTable objects

=head1 DESCRIPTION

Easily create Google DataTable objects without worrying too much about typed
data

=head1 OVERVIEW

Google's excellent Visualization suite requires you to format your Javascript
data very carefully. It's entirely possible to do this by hand, especially with
the help of the most excellent L<JSON::XS> but it's a bit fiddly, largely
because Perl doesn't natively support data types and Google's API accepts a
super-set of JSON.

This module is attempts to hide the gory details of preparing your data before
sending it to a JSON serializer - more specifically, hiding some of the hoops
that have to be jump through for making sure your data serializes to the right
data types.

More about the
L<Google Visualization API|http://code.google.com/apis/visualization/documentation/reference.html#dataparam>.

Every effort has been made to keep naming conventions as close as possible to
those in the API itself.

B<To use this module, a reasonable knowledge of Perl is assumed. You should be
familiar with L<Perl references|perlreftut> and L<Perl objects|perlboot>.>

=head1 SYNOPSIS

 use Data::Google::Visualization::DataTable;

 my $datatable = Data::Google::Visualization::DataTable->new();

 $datatable->add_columns(
 	{ id => 'date',     label => "A Date",        type => 'date', p => {}},
 	{ id => 'datetime', label => "A Datetime",    type => 'datetime' },
 	{ id => 'timeofday',label => "A Time of Day", type => 'timeofday' },
 	{ id => 'bool',     label => "True or False", type => 'boolean' },
 	{ id => 'number',   label => "Number",        type => 'number' },
 	{ id => 'string',   label => "Some String",   type => 'string' },
 );

 $datatable->add_rows(

 # Add as array-refs
 	[
 		{ v => DateTime->new() },
 		{ v => Time::Piece->new(), f => "Right now!" },
 		{ v => [6, 12, 1], f => '06:12:01' },
 		{ v => 1, f => 'YES' },
 		15.6, # If you're getting lazy
 		{ v => 'foobar', f => 'Foo Bar', p => { display => 'none' } },
 	],

 # And/or as hash-refs (but only if you defined id's for each of your columns)
 	{
 		date      => DateTime->new(),
 		datetime  => { v => Time::Piece->new(), f => "Right now!" },
 		timeofday => [6, 12, 1],
 		bool      => 1,
 		number    => 15.6,
 		string    => { v => 'foobar', f => 'Foo Bar' },
 	},

 );

 # Get the data...

 # Fancy-pants
 my $output = $self->output_json(
 	columns => ['date','number','string' ],
 	pretty  => 1,
 );

 # Vanilla
 my $output = $self->output_json();

=head1 COLUMNS, ROWS AND CELLS

We've tried as far as possible to stay as close as possible to the underlying
API, so make sure you've had a good read of:
L<Google Visualization API|http://code.google.com/apis/visualization/documentation/reference.html#dataparam>.

=head2 Columns

I<Columns> are specified using a hashref, and follow exactly the format of the
underlying API itself. All of C<type>, C<id>, C<label>, C<pattern>, and C<p> are
supported. The contents of C<p> will be passed directly to L<JSON::XS> to
serialize as a whole.

=head2 Rows

A row is either a hash-ref where the keys are column IDs and the values are
I<cells>, or an array-ref where the values are I<cells>.

=head2 Cells

I<Cells> can be specified in several ways, but the best way is using a hash-ref
that exactly conforms to the API. C<v> is NOT checked against your data type -
but we will attempt to convert it. C<f> needs to be a string if you provide it.
C<p> will be bassed directly to L<JSON::XS>.

For any of the date-like fields (C<date>, C<datetime>, C<timeofday>), you can
pass in 4 types of values. We accept L<DateTime> objects, L<Time::Piece>
objects, epoch seconds (as a string - converted internally using
L<localtime|perlfunc/localtime>), or an array-ref of values that will be passed
directly to the resulting Javascript Date object eg:

 Perl:
  date => [ 5, 4, 3 ]
 JS:
  new Date( 5, 4, 3 )

Remember that JS dates 0-index the month.

For non-date fields, if you specify a cell using a string or number, rather than
a hashref, that'll be mapped to a cell with C<v> set to the string you
specified.

C<boolean>: we test the value you pass in for truth, the Perl way.

=head1 METHODS

=head2 new

Constructor. Accepts no arguments, returns a new object.

=cut

sub new {
	my $class = shift;
	my $self = {
		columns              => [],
		column_mapping       => {},
		rows                 => [],
		json_xs              => JSON::XS->new()->canonical(1),
		all_columns_have_ids => 0,
		column_count         => 0,
		pedantic             => 1
	};
	bless $self, $class;
	return $self;
}

=head2 add_columns

Accepts zero or more columns, in the format specified above, and adds them to
our list of columns. Returns the object. You can't call this method after you've
called C<add_rows> for the first time.

=cut

our %ACCEPTABLE_TYPES = map { $_ => 1 } qw(
	date datetime timeofday boolean number string
);

our %JAVASCRIPT_RESERVED = map { $_ => 1 } qw(
	break case catch continue default delete do else finally for function if in
	instanceof new return switch this throw try typeof var void while with
	abstract boolean byte char class const debugger double enum export extends
	final float goto implements import int interface long native package private
	protected public short static super synchronized throws transient volatile
	const export import
);

sub add_columns {
	my ($self, @columns) = @_;

	croak "You can't add columns once you've added rows" if @{$self->{'rows'}};

	# Add the columns to our internal store
	for my $column ( @columns ) {

		# Check the type
		my $type = $column->{'type'};
		croak "Every column must have a 'type'" unless $type;
		croak "Unknown column type '$type'" unless $ACCEPTABLE_TYPES{ $type };

		# Check label and ID are sane
		for my $key (qw( label id pattern ) ) {
			if ( $column->{$key} && ref( $column->{$key} ) ) {
				croak "'$key' needs to be a simple string";
			}
		}

		# Check the 'p' column is ok if it was provided, and convert now to JSON
		if ( defined($column->{'p'}) ) {
			croak "'p' must be a reference" unless ref( $column->{'p'} );
			eval { $self->json_xs_object->encode( $column->{'p'} ) };
			croak "Serializing 'p' failed: $@" if $@;
		}

		# ID must be unique
		if ( $column->{'id'} ) {
			my $id = $column->{'id'};
			if ( grep { $id eq $_->{'id'} } @{ $self->{'columns'} } ) {
				croak "We already have a column with the id '$id'";
			}
		}

		# Pedantic checking of that ID
		if ( $self->pedantic ) {
			if ( $column->{'id'} ) {
				if ( $column->{'id'} !~ m/^[a-zA-Z0-9_]+$/ ) {
					carp "The API recommends that t ID's should be both simple:"
						. $column->{'id'};
				} elsif ( $JAVASCRIPT_RESERVED{ $column->{'id'} } ) {
					carp "The API recommends avoiding Javascript reserved " .
						"words for IDs: " . $column->{'id'};
				}
			}
		}

		# Add that column to our collection
		push( @{ $self->{'columns'} }, $column );
	}

	# Reset column statistics
	$self->{'column_mapping'} = {};
	$self->{'column_count'  } = 0;
	$self->{'all_columns_have_ids'} = 1;

	# Map the IDs to column indexes, redo column stats, and encode the column
	# data
	my $i = 0;
	for my $column ( @{ $self->{'columns'} } ) {

		# Encode as JSON
		delete $column->{'json'};
		my $column_json = $self->json_xs_object->encode( $column );
		$column->{'json'} = $column_json;

		# Column mapping
		if ( $column->{'id'} ) {
			$self->{'column_mapping'}->{ $column->{'id'} } = $i;
		} else {
			$self->{'all_columns_have_ids'} = 0;
		}
		$i++;
	}

	return $self;
}

=head2 add_rows

Accepts zero or more rows, either as a list of hash-refs or a list of
array-refs. If you've provided hash-refs, we'll map the key name to the column
via its ID (you must have given every column an ID if you want to do this, or
it'll cause a fatal error).

If you've provided array-refs, we'll assume each cell belongs in subsequent
columns - your array-ref must have the same number of members as you have set
columns.

=cut

sub add_rows {
	my ( $self, @rows_to_add ) = @_;

	# Loop over our input rows
	for my $row (@rows_to_add) {

		my @columns;

		# Map hash-refs to columns
		if ( ref( $row ) eq 'HASH' ) {

			# We can't be going forward unless they specified IDs for each of
			# their columns
			croak "All your columns must have IDs if you want to add hashrefs" .
				" as rows" unless $self->{'all_columns_have_ids'};

			# Loop through the keys, populating @columns
			for my $key ( keys %$row ) {
				# Get the relevant column index for the key
				unless ( exists $self->{'column_mapping'}->{ $key } ) {
					croak "Couldn't find a column with id '$key'";
				}
				my $index = $self->{'column_mapping'}->{ $key };

				# Populate @columns with the data-type and value
				$columns[ $index ] = [
					$self->{'columns'}->[ $index ]->{'type'},
					$row->{ $key }
				];

			}

		# Map array-refs to columns
		} elsif ( ref( $row ) eq 'ARRAY' ) {

			# Populate @columns with the data-type and calue
			my $i = 0;
			for my $col (@$row) {
				$columns[ $i ] = [
					$self->{'columns'}->[ $i ]->{'type'},
					$col
				];
				$i++;
			}

		# Rows must be array-refs or hash-refs
		} else {
			croak "Rows must be array-refs or hash-refs: $row";
		}

		# Convert each cell in to the long cell format
		my @formatted_columns;
		for ( @columns ) {
			my ($type, $column) = @$_;

			if ( ref( $column ) eq 'HASH' ) {
				# Check f is a simple string if defined
				if ( defined($column->{'f'}) && ref( $column->{'f'} ) ) {
					croak "Cell's 'f' values must be strings: " .
						$column->{'f'};
				}
				# If p is defined, check it serializes
				if ( defined($column->{'p'}) ) {
					croak "'p' must be a reference"
						unless ref( $column->{'p'} );
					eval { $self->json_xs_object->encode( $column->{'p'} ) };
					croak "Serializing 'p' failed: $@" if $@;
				}
				# Complain about any unauthorized keys
				if ( $self->pedantic ) {
					for my $key ( keys %$column ) {
						carp "'$key' is not a recognized key"
							unless $key =~ m/^[fvp]$/;
					}
				}
				push( @formatted_columns, [ $type, $column ] );
			} else {
				push( @formatted_columns, [ $type, { v => $column } ] );
			}
		}

		# Serialize each cell
		my @cells;
		for (@formatted_columns) {
			my ($type, $cell) = @$_;

			# Force 'f' to be a string
			if ( defined( $cell->{'f'} ) ) {
				$cell->{'f'} .= '';
			}

			# Convert boolean
			if ( $type eq 'boolean' ) {
				$cell->{'v'} = $cell->{'v'} ? \1 : \0;
				push(@cells, $self->json_xs_object->encode( $cell ) );

			# Convert number
			} elsif ( $type eq 'number' ) {
				$cell->{'v'} += 0;
				push(@cells, $self->json_xs_object->encode( $cell ) );

			# Convert string
			} elsif ( $type eq 'string' ) {
				$cell->{'v'} .= '';
				push(@cells, $self->json_xs_object->encode( $cell ) );

			# It's a date!
			} else {
				my @date_digits;

				# Date digits specified manually
				if ( ref( $cell->{'v'} ) eq 'ARRAY' ) {
					@date_digits = @{ $cell->{'v'} };
				# We're going to have to retrieve them ourselves
				} else {
					my @initial_date_digits;

					# Epoch timestamp
					if (! ref( $cell->{'v'} ) ) {
						my ($sec,$min,$hour,$mday,$mon,$year) =
							localtime( $cell->{'v'} );
						@initial_date_digits =
							( $year, $mon, $mday, $hour, $min, $sec );

					} elsif ( $cell->{'v'}->isa('DateTime') ) {
						my $dt = $cell->{'v'};
						@initial_date_digits = (
							$dt->year, ( $dt->mon - 1 ), $dt->day,
							$dt->hour, $dt->min, $dt->sec, $dt->millisecond
						);

					} elsif ( $cell->{'v'}->isa('Time::Piece') ) {
						my $tp = $cell->{'v'};
						@initial_date_digits = (
							$tp->year, $tp->_mon, $tp->mday,
							$tp->hour, $tp->min, $tp->sec
						);

					} else {
						croak "Unknown date format";
					}

					if ( $type eq 'date' ) {
						@date_digits = @initial_date_digits[ 0 .. 2 ];
					} elsif ( $type eq 'datetime' ) {
						@date_digits = @initial_date_digits[ 0 .. 5 ];
					} else { # Time of day
						@date_digits = @initial_date_digits[ 3, -1 ];
					}
				}

				my $json_date = join ', ', @date_digits;
				if ( $type eq 'timeofday' ) {
					$json_date = '[' . $json_date . ']';
				} else {
					$json_date = 'new Date( ' . $json_date . ' )';
				}

				my $placeholder = '%%%PLEHLDER%%%';
				$cell->{'v'} = $placeholder;
				my $json_string = $self->json_xs_object->encode( $cell );
				$json_string =~ s/"$placeholder"/$json_date/;
				push(@cells, $json_string );
			}
		}

		push( @{ $self->{'rows'} }, \@cells );
	}

	return $self;
}

=head2 pedantic

We do some data checking for sanity, and we'll issue warnings about things the
API considers bad data practice - using reserved words or fancy characters on
IDs so far. If you don't want that, simple say:

 $object->pedantic(0);

Defaults to true.

=cut

sub pedantic {
	my ($self, $arg) = @_;
	$self->{'pedantic'} = $arg if defined $arg;
	return $self->{'pedantic'};
}

=head2 json_xs_object

You may want to configure your L<JSON::XS> object in some magical way. This is
a read/write accessor to it. If you didn't understand that, or why you'd want
to do that, you can ignore this method.

=cut

sub json_xs_object {
	my ($self, $arg) = @_;
	$self->{'json_xs'} = $arg if defined $arg;
	return $self->{'json_xs'};
}

=head2 output_json

Returns a JSON serialization of your object. You can optionally specify two
parameters:

C<pretty> - I<bool> - defaults to false - that specifies if you'd like your JSON
spread-apart with whitespace. Useful for debugging.

C<columns> - I<array-ref of strings> - pick out certain columns only (and in the
order you specify). If you don't provide an argument here, we'll use them all
and in the order set in C<add_columns>.

=cut

sub output_json {
	my ($self, %params) = @_;

	my ($columns, $rows) = $self->_select_data( %params );

	my ($t, $s, $n) = ('','','');
	if ( $params{'pretty'} ) {
		$t = "    ";
		$s = " ";
		$n = "\n";
	}

	# Columns
	my $columns_string = join ',' .$n.$t.$t, @$columns;

	# Rows
	my @rows = map {
		my $individual_row_string = join ',' .$n.$t.$t.$t, @$_;
		'{ "c":[' .$n.$t.$t.$t. $individual_row_string .$n.$t.$t. ']}';
	} @$rows;
	my $rows_string = join ',' . $n . $t . $t, @rows;

	return
		'{' .$n.
		$t.     '"cols": [' .$n.
		$t.     $t.    $columns_string .$n.
		$t.     '],' .$n.
		$t.     '"rows": [' .$n.
		$t.     $t.    $rows_string .$n.
		$t.     ']' .$n.
		'}';
}

sub _select_data {
	my ($self, %params) = @_;

	my $rows    = dclone $self->{'rows'};
	my $columns = [map { $_->{'json'} } @{$self->{'columns'}}];

	# Select certain columns by id only
	if ( $params{'columns'} && @{ $params{'columns'} } ) {
		my @column_spec;

		# Get the name of each column
		for my $column ( @{$params{'columns'}} ) {

		# And push it's place in the array in to our specification
			my $index = $self->{'column_mapping'}->{ $column };
			croak "Couldn't find a column named '$column'" unless
				defined $index;
			push(@column_spec, $index);
		}

		# Grab the column selection
		my @new_columns;
		for my $index (@column_spec) {
			my $column = splice( @{$columns}, $index, 1, '' );
			push(@new_columns, $column);
		}

		# Grab the row selection
		my @new_rows;
		for my $original_row (@$rows) {
			my @new_row;
			for my $index (@column_spec) {
				my $column = splice( @{$original_row}, $index, 1, '' );
				push(@new_row, $column);
			}
			push(@new_rows, \@new_row);
		}

		$rows = \@new_rows;
		$columns = \@new_columns;
	}

	return ( $columns, $rows );
}

=head1 BUG BOUNTY

Find a reproducible bug, file a bug report, and I (Peter Sergeant) will donate
$10 to The Perl Foundation (or Wikipedia). Feature Requests are not bugs :-)
Offer subject to author's discretion...

=head1 AUTHOR

Peter Sergeant C<pete@clueball.com> on behalf of
L<Investor Dynamics|http://www.investor-dynamics.com/> - I<Letting you know what
your market is thinking>.

=head1 SEE ALSO

L<Python library that does the same thing|http://code.google.com/p/google-visualization-python/>

L<JSON::XS> - The underlying module

L<Google Visualization API|http://code.google.com/apis/visualization/documentation/reference.html#dataparam>.

=head1 COPYRIGHT

Copyright 2010 Investor Dynamics Ltd, some rights reserved.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
