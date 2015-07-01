use 5.010000;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	NAME => 'Starflight',
	VERSION_FROM => 'lib/Starflight.pm', # finds $VERSION
	PREREQ_PM => {
		'AnyEvent' => '7.07',
		'AnyEvent::Hiredis' => '0.04',
		'AnyEvent::HTTP' => '2.15',
		'Coro' => '6.41',
		'Coro::Channel::Factory' => '1.01',
		'Coro::EV' => '6.41',
		'EV' => '4.15',
		'Exception::Class' => '1.37',
		'HTTP::Date' => '6.02',
		'HTTP::Headers::Util' => '6.03',
		'IO::Compress::Bzip2' => '2.033',
		'IO::Compress::Gzip' => '2.033',
		'IO::Compress::RawDeflate' => '2.033',
		'IO::Uncompress::Bunzip2' => '2.033',
		'IO::Uncompress::Gunzip' => '2.033',
		'IO::Uncompress::RawInflate' => '2.033',
		'JSON' => '2.61',
		'Log::Log4perl' => '1.41',
		'Mojolicious' => '6.05',
		'Plack' => '1.0030',
		'Pod::Usage' => '1.36',
		'POSIX::strftime::Compiler' => '0.40',
		'Scalar::Util' => '1.23',
		'Text::Template' => '1.45',
		'Try::Tiny' => '0.19'   
	},
	EXE_FILES => ['bin/starflight'], 
	META_MERGE => {
		'meta-spec' => { version => 2 },
		resources => {
			repository => {
				type => 'git',
				url  => 'https://github.com/phillipod/Starflight.git',
				web  => 'https://github.com/phillipod/Starflight',
			},
		},
	},
	($] >= 5.005 ?	 ## Add these new keywords supported since 5.005
	  (ABSTRACT_FROM => 'lib/Starflight.pm', # retrieve abstract from module
	   AUTHOR	=> 'Phillip O\'Donnell <podonnell@cpan.org>') : ()),
);
