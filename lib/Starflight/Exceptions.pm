package Starflight::Exceptions;

use Starflight::Exceptions::Base;

BEGIN { $Exception::Class::BASE_EXC_CLASS = 'Starflight::Exceptions::Base'; }

use Exception::Class (
	'Starflight::Exception::HTTP' => { 
		description => 'Base Exception',
		fields => [ 'http_status_code', 'http_status_text' ],
	},
	
	'Starflight::Exception::HTTP::RequestValidation' => {
		isa => 'Starflight::Exception::HTTP',
		description => 'Base Exception for all Request Validation exceptions',
	},
	
	'Starflight::Exception::Protocol::Version::Unsupported' => {
		isa => 'Starflight::Exception::HTTP::RequestValidation',
		description => 'HTTP Protocol Version Unsupported',
		fields => [ 'http_version_supplied', 'http_version_expected' ],
		defaults => { 'http_status_code' => 505, 'http_status_text' => 'HTTP Version Not Supported' },
	},
	
	'Starflight::Exception::Headers::Host::Unknown' => {
		isa => 'Starflight::Exception::HTTP::RequestValidation',
		description => 'Host Header Unknown',
		fields => [ 'http_redirect_location' ],
		defaults => { 'http_status_code' => 302, 'http_status_text' => 'Found' },
	},
	
	'Starflight::Exception::Headers::Host::Absent' => {
		isa => 'Starflight::Exception::HTTP::RequestValidation',
		description => 'Host Header Absent',
		defaults => { 'http_status_code' => 400, 'http_status_text' => 'Bad Request' },
	},
	
	'Starflight::Exception::HTTP::Proxy' => {
		isa => 'Starflight::Exception::HTTP',
		description => 'Base Exception for all Proxy exceptions',
	},
	
	'Starflight::Exception::Proxy::ConnectionError' => {
		isa => 'Starflight::Exception::HTTP::Proxy',
		description => 'Error during connection establishment or proxy handshake.',
		defaults => { 'http_status_code' => 503, 'http_status_text' => 'Service Unavailable' },
	},

	'Starflight::Exception::Proxy::RequestError' => {
		isa => 'Starflight::Exception::HTTP::Proxy',
		description => 'Error during TLS negotiation, request sending or header processing.',
		defaults => { 'http_status_code' => 503, 'http_status_text' => 'Service Unavailable' },
	},

	'Starflight::Exception::Proxy::ResponseError' => {
		isa => 'Starflight::Exception::HTTP::Proxy',
		description => 'Error during body receiving or processing.',
		defaults => { 'http_status_code' => 503, 'http_status_text' => 'Service Unavailable' },
	},

	'Starflight::Exception::Proxy::OtherError' => {
		isa => 'Starflight::Exception::HTTP::Proxy',
		description => 'Other, usually nonretryable, error (garbled URL etc.).',
		defaults => { 'http_status_code' => 503, 'http_status_text' => 'Service Unavailable' },
	},
	
	'Starflight::Exception::HTTP::Redis' => {
		isa => 'Starflight::Exception::HTTP',
		description => 'Base Exception for all Redis exceptions',
	},
	
	'Starflight::Exception::Redis::Error' => {
		isa => 'Starflight::Exception::HTTP::Redis',
		description => 'Error while fetching data from Redis',
		defaults => { 'http_status_code' => 503, 'http_status_text' => 'Service Unavailable' },
	},

	'Starflight::Exception::Redis::NoResult' => {
		isa => 'Starflight::Exception::HTTP::Redis',
		description => 'No result returned from Redis',
		defaults => { 'http_status_code' => 503, 'http_status_text' => 'Service Unavailable' },
	},
	
);


1;
