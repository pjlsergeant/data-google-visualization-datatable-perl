#!/usr/bin/perl

use strict;
use warnings;
use Data::Google::Visualization::DataTable;

use Test::More tests => 4;

my $datatable = Data::Google::Visualization::DataTable->new();

$datatable->add_columns(
	{ id => 'bool',     label => "True or False", type => 'boolean' },
	{ id => 'number',   label => "Number",        type => 'number' },
	{ id => 'string',   label => "Some String",   type => 'string',
		p => { display => 'none' } },
);

$datatable->add_rows(
 # Add as array-refs
 	[
 		{ v => 1, f => 'YES' },
 		15.6,
 		{ v => 'foobar', f => 'Foo Bar', p => { display => 'none' } },
	],
	{
 		bool      => 1,
 		number    => 15.6,
 		string    => { v => 'foobar', f => 'Foo Bar' },
	},
);

is(
	$datatable->output_json( pretty => 1 ),
	q!{
    "cols": [
        {"id":"bool","label":"True or False","type":"boolean"},
        {"id":"number","label":"Number","type":"number"},
        {"id":"string","label":"Some String","p":{"display":"none"},"type":"string"}
    ],
    "rows": [
        {"c":[
            {"f":"YES","v":true},
            {"v":15.6},
            {"f":"Foo Bar","p":{"display":"none"},"v":"foobar"}
        ]},
        {"c":[
            {"v":true},
            {"v":15.6},
            {"f":"Foo Bar","v":"foobar"}
        ]}
    ]
}!,
	"Pretty JSON rendering matches"
);

is(
	$datatable->output_json(),
	q!{"cols": [{"id":"bool","label":"True or False","type":"boolean"},{"id":"number","label":"Number","type":"number"},{"id":"string","label":"Some String","p":{"display":"none"},"type":"string"}],"rows": [{"c":[{"f":"YES","v":true},{"v":15.6},{"f":"Foo Bar","p":{"display":"none"},"v":"foobar"}]},{"c":[{"v":true},{"v":15.6},{"f":"Foo Bar","v":"foobar"}]}]}!,
	"Compact JSON rendering matches"
);

is(
	$datatable->output_json( pretty => 1, columns => ['bool'] ),
	q!{
    "cols": [
        {"id":"bool","label":"True or False","type":"boolean"}
    ],
    "rows": [
        {"c":[
            {"f":"YES","v":true}
        ]},
        {"c":[
            {"v":true}
        ]}
    ]
}!,
	"Specific column rendering works"
);

# Label-less example
my $datatable2 = Data::Google::Visualization::DataTable->new();
$datatable2
	->add_columns({ type => 'string' },{ type => 'number', label => 'hits' })
	->add_rows( [ 'One', 1 ], ['Two', { v => 2, f => '2t' } ] );

is(
	$datatable2->output_json(),
	q!{"cols": [{"type":"string"},{"label":"hits","type":"number"}],"rows": [{"c":[{"v":"One"},{"v":1}]},{"c":[{"v":"Two"},{"f":"2t","v":2}]}]}!,
	"Everything works without IDs"
);



