use ExtUtils::MakeMaker;
 
&WriteMakefile(
	NAME           => 'Data::Google::Visualization::DataTable',
	DISTNAME       => 'Data-Google-Visualization-DataTable',
	VERSION_FROM   => 'lib/Data/Google/Visualization/DataTable.pm', 
	PREREQ_PM      => { 
		'JSON::XS' => '2.0',
	}               
);

