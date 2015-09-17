package Starflight::Config::Model::Redis;

use 5.010000;
use strict;
use warnings;

use base 'Starflight::Model::Redis';

use Coro;
use AnyEvent;
use Text::Template;

use Starflight::Exceptions;

our $VERSION = $Starflight::VERSION;

use Data::Dumper;

sub new {
	my $class = shift;
	my $parent = shift;
	
	my $self = {};

	bless($self, $class);

	$self->{logger} = Log::Log4perl::get_logger('Starflight::Config::Model::Redis');

	$self->{parent} = $parent;
	$self->{settings} = $parent->{settings}{redis};
	
	$self->{queue} = $self->channel('Starflight::Config::Model::Redis.worker_queue');
	
	return $self;
}

sub get_host_serial {
	my $self = shift;
	my $serial_selector = shift;
	my $serial_key = undef;
	
	if ($serial_selector->{-key}) {
		$serial_key = $serial_selector->{-key};
	} else {
		$serial_key = "config://$serial_selector->{-name}/server/";
	}
	
	my $keyData = $self->command([ "HGET", $serial_key, "sn" ]);

	$self->{logger}->debug("serial key: $serial_key key data: $keyData");
	
	return $keyData;
}

sub get_trigger_serial {
	my $self = shift;
	my $trigger_key = shift;

	my $keyData = $self->command([ "HGET", $trigger_key, "sn" ]);

	$self->{logger}->debug("trigger key: $trigger_key serial data: $keyData");
	
	return $keyData;
}

sub load_host_config {
	my $self = shift;
	my $host_selector = shift;
	my $host_config = shift;

	my $host_key = undef;
	
	if ($host_selector->{-key}) {
		$host_key = $host_selector->{-key};
	} else {
		$host_key = "config://$host_selector->{-name}/";
	}

	my $keyData = $self->command([ "ZRANGEBYSCORE", $host_key, "-inf", "+inf" ]);

	my @config_keys = @{$keyData};
	my $load_result = undef;
		
	foreach my $key (@config_keys) {
		if ($key =~ /^config:\/\/[^\/]+\/$/) {
			# This host inherits properties from another definition.
			$self->{logger}->debug("host key '$host_key' inheriting from '$key'");
			
			$load_result = $self->load_host_config({ -key => $key }, $host_config);
		} elsif ($key =~ /^config:\/\/[^\/]+\/server\/$/) {
			$self->{logger}->debug("host key '$host_key' loading server definition from '$key'");

			$host_config->{server} = {};

			$load_result = $self->load_host_server_config({ -key => $key }, $host_config->{server}); 
		} elsif ($key =~ /^config:\/\/[^\/]+\/headers\/(request|response)\/(add|remove|replace|transform)\/$/) {
			my $type = $1;
			my $action = $2;

			$self->{logger}->debug("host key '$host_key' loading header $type/$action definition from '$key'");
			
			$host_config->{headers}{$type}{$action} = {};
			
			if ($action eq "add") {
				$load_result = $self->load_host_headers_add($key, $host_config->{headers}{$type}{$action});
			} elsif ($action eq "remove") {
				$load_result = $self->load_host_headers_remove($key, $host_config->{headers}{$type}{$action});
			} elsif ($action eq "replace") {
				$load_result = $self->load_host_headers_replace($key, $host_config->{headers}{$type}{$action});
			} elsif ($action eq "transform") {
				$load_result = $self->load_host_headers_transform($key, $host_config->{headers}{$type}{$action});
			} else {
				# unknown action type	
				$self->{logger}->warn("host key '$host_key' loading unknown header action type '$action' definition from '$key'");
			}
		} elsif ($key =~ /^config:\/\/[^\/]+\/cookies\/(add|replace)\/$/) {
			my $action = $1;

			$self->{logger}->debug("host key '$host_key' loading cookie $action definition from '$key'");
			
			$host_config->{cookies}{$action} = {};
			
			if ($action eq "add") {
				$load_result = $self->load_host_cookies_add($key, $host_config->{cookies}{$action});
			} elsif ($action eq "replace") {
				$load_result = $self->load_host_cookies_replace($key, $host_config->{cookies}{$action});
			} else {
				# unknown action type	
				$self->{logger}->warn("host key '$host_key' loading unknown cookie action type '$action' definition from '$key'");
			}
		} elsif ($key =~ /^config:\/\/[^\/]+\/content\/(request|response)\/(add|remove|replace|transform)\/(selection)\/$/) {
			my $type = $1;
			my $action = $2;
			my $location = $3;

			$self->{logger}->debug("host key '$host_key' loading content $type/$action/$location definition from '$key'");
			
			$host_config->{content}{$type}{$location} = {};
			
			if ($action eq "add") {
				$load_result = $self->load_host_content_add($key, $location, $host_config->{content}{$type}{$location});
			} elsif ($action eq "remove") {
				$load_result = $self->load_host_content_remove($key, $location, $host_config->{content}{$type}{$location});
			} elsif ($action eq "replace") {
				$load_result = $self->load_host_content_replace($key, $location, $host_config->{content}{$type}{$location});
			} elsif ($action eq "transform") {
				$load_result = $self->load_host_content_transform($key, $location, $host_config->{content}{$type}{$location});
			} else {
				# unknown action type	
				$self->{logger}->warn("host key '$host_key' loading unknown content action type '$action' definition from '$key'");
			}
		} elsif ($key =~ /^config:\/\/[^\/]+\/content\/(request|response)\/(transform)\/(global)\/$/) {
			my $type = $1;
			my $action = $2;
			my $location = $3;
			
			$self->{logger}->debug("host key '$host_key' loading content $type/$action/$location definition from '$key'");

			$host_config->{content}{$type}{$location} = {};
			
			if ($action eq "transform") {
				$load_result = $self->load_host_content_transform($key, $location, $host_config->{content}{$type}{$location});
			} else {
				# unknown action type	
				$self->{logger}->warn("host key '$host_key' loading unknown content action type '$action' definition from '$key'");
			}
		} elsif ($key =~ /^config:\/\/[^\/]+\/uri\/(routes)\/$/) {
			my $type = $1;
			$self->{logger}->debug("host key '$host_key' loading uri $type definition from '$key'");

			$host_config->{uri}{routes} = {};
			
			if ($type eq "routes") {
				$load_result = $self->load_host_uri_routes($key, $host_config->{uri}{routes});
			} else {
				# unknown type	
				$self->{logger}->warn("host key '$host_key' loading unknown uri type '$type' definition from '$key'");
			}
		} elsif ($key =~ /^trigger:\/\/[^\/]+\/$/) {
			$self->{logger}->debug("host key '$host_key' loading trigger list from '$key'");

			$host_config->{triggers} = {};

			$load_result = $self->load_host_triggers($key, $host_key, $host_config->{triggers}); 
		} else {
			$self->{logger}->warn("host key '$host_key' attempted to load unknown key '$key'");	
		}
	}
	
	$self->{logger}->debug("loaded host config: " . Dumper($host_config));
	
	return 1;
}

sub load_host_server_config {
	my $self = shift;
	my $host_selector = shift;
	my $server_config = shift;

	my $key = undef;
	
	if ($host_selector->{-key}) {
		$key = $host_selector->{-key};
	} else {
		$key = "config://$host_selector->{-name}/server/";
	}

	my $keyData = $self->command([ "HGETALL", $key ]);

	my %result_hash = @{$keyData};
	foreach my $result_key (keys %result_hash) {
		$server_config->{$result_key} = $result_hash{$result_key};	
	}
}

sub load_host_headers_add {
	my $self = shift;
	my $key = shift;
	my $headers_add = shift;
	
	my $keyData = $self->command([ "HGETALL", $key ]);
	
	my %result_hash = @{$keyData};
	foreach my $result_key (keys %result_hash) {
		$headers_add->{$result_key} = $result_hash{$result_key};	
	}
}

sub load_host_headers_remove {
	my $self = shift;
	my $key = shift;
	my $headers_remove = shift;

	my $keyData = $self->command([ "SMEMBERS", $key ]);
	
	my %result_hash = @{$keyData};
	foreach my $result_key (keys %result_hash) {
		$headers_remove->{$result_key} = $result_hash{$result_key};	
	}
}

sub load_host_headers_replace {
	my $self = shift;
	my $key = shift;
	my $headers_replace = shift;
	
	my $keyData = $self->command([ "HGETALL", $key ]);
	
	my %result_hash = @{$keyData};
	foreach my $result_key (keys %result_hash) {
		$headers_replace->{$result_key} = $result_hash{$result_key};	
	}
}

sub load_host_headers_transform {
	my $self = shift;
	my $key = shift;
	my $headers_transform = shift;

	my $keyData = $self->command([ "HGETALL", $key ]);

	my %result_hash = @{$keyData};
	foreach my $result_key (keys %result_hash) {
		if (!$headers_transform->{$result_key}) { $headers_transform->{$result_key} = {}; }

		my $load_result = $self->load_host_headers_transformation($result_hash{$result_key}, $headers_transform->{$result_key}); 		
	}
}

sub load_host_headers_transformation {
	my $self = shift;
	my $key = shift;
	my $header_transformation = shift;

	my $keyData = $self->command([ "HGETALL", $key ]);

	my %result_hash = @{$keyData};

	foreach my $result_key (keys %result_hash) {
		if ($result_key eq "match") {
			if ($result_hash{'type'} eq "text") {
				$result_hash{$result_key} = quotemeta($result_hash{$result_key});
			}

			$header_transformation->{$result_key} = qr/$result_hash{$result_key}/;
		} else {
			$header_transformation->{$result_key} = $result_hash{$result_key};
		}	
	}
}

sub load_host_cookies_add {
	my $self = shift;
	my $key = shift;
	my $cookies_add = shift;
	
	my $keyData = $self->command([ "HGETALL", $key ]);
	
	my %result_hash = @{$keyData};
	foreach my $result_key (keys %result_hash) {
		if (!$cookies_add->{$result_key}) { $cookies_add->{$result_key} = {}; }

		my $load_result = $self->load_host_cookie($result_hash{$result_key}, $cookies_add->{$result_key}); 
	}
}

sub load_host_cookies_replace {
	my $self = shift;
	my $key = shift;
	my $cookies_replace = shift;
	
	my $keyData = $self->command([ "HGETALL", $key ]);
	
	my %result_hash = @{$keyData};
	foreach my $result_key (keys %result_hash) {
		if (!$cookies_replace->{$result_key}) { $cookies_replace->{$result_key} = {}; }

		my $load_result = $self->load_host_cookie($result_hash{$result_key}, $cookies_replace->{$result_key}); 
	}
}

sub load_host_cookie {
	my $self = shift;
	my $key = shift;
	my $cookie = shift;

	my $keyData = $self->command([ "HGETALL", $key ]);

	my %result_hash = @{$keyData};

	foreach my $result_key (keys %result_hash) {
	   $cookie->{$result_key} = $result_hash{$result_key};	
	}
	
	if (exists $result_hash{trigger}) {
	   $cookie->{trigger} = new Text::Template(TYPE => 'STRING', SOURCE => $result_hash{trigger});
	   $cookie->{trigger}->compile();
	}
} 


sub load_host_content_transform {
	my $self = shift;
	my $key = shift;
	my $location = shift;
	my $content_transform = shift;

	my $keyData = $self->command([ "HGETALL", $key ]);
 
	my %result_hash = @{$keyData};
	foreach my $content_type (keys %result_hash) {
		if (!$content_transform->{$content_type}) { $content_transform->{$content_type} = { transform => [ ] }; }

		my $load_result = $self->load_host_content_transformation($result_hash{$content_type}, $location, $content_transform->{$content_type}{transform}); 		
	}
}

sub load_host_content_transformation {
	my $self = shift;
	my $key = shift;
	my $location = shift;
	my $content_transformation = shift;

	my $keyData = $self->command([ "ZRANGEBYSCORE", $key, "-inf", "+inf" ]);

	my @result_keys = @{$keyData};

	my $load_result = undef;
	
	foreach my $result_key (@result_keys) {
		if ($location eq "selection") {
			$load_result = $self->load_host_content_transformation_selection($result_key, $content_transformation);
		} elsif ($location eq "global") {
			$load_result = $self->load_host_content_transformation_global($result_key, $content_transformation);
		}
	}
}

sub load_host_content_transformation_selection {
	my $self = shift;
	my $key = shift;
	my $content_transformation = shift;

	my $keyData = $self->command([ "HGETALL", $key ]);

	my %result_hash = @{$keyData};


	foreach my $result_key (keys %result_hash) {
		my %transform = ( selector => $result_key );
			
		my $command = $result_hash{$result_key};
					
		if ($command =~ /^(substitute)\s+([^\s]+)\s+"(.*?)"\s+"(.*?)"\s*$/i) {
			$transform{transform} = lc($1);
			$transform{target} = lc($2);
			$transform{match} = $3;
			$transform{replace} = $4;
		}

		push(@{$content_transformation}, \%transform);
	}
	
}

sub load_host_content_transformation_global {
	my $self = shift;
	my $key = shift;
	my $content_transformation = shift;

	my $keyData = $self->command([ "HGETALL", $key ]);

	my %result_hash = @{$keyData};

	my $transform = ();
	foreach my $result_key (keys %result_hash) {
		if ($result_key eq "match") {
			if ($result_hash{'type'} eq "text") {
				$result_hash{$result_key} = quotemeta($result_hash{$result_key});
			}

			$transform->{$result_key} = qr/$result_hash{$result_key}/;
		} else {
			$transform->{$result_key} = $result_hash{$result_key};
		}	
	}
	push(@{$content_transformation}, $transform);
	
	#print Dumper($content_transformation);
}

sub load_host_uri_routes {
	my $self = shift;
	my $key = shift;
	my $routes = shift;

	my $keyData = $self->command([ "HGETALL", $key ]);

	my %result_hash = @{$keyData};
	foreach my $result_key (keys %result_hash) {
		$self->load_host_uri_route_definition($result_hash{$result_key}, \$routes->{$result_key});
	}
}

sub load_host_uri_route_definition {
	my $self = shift;
	my $key = shift;
	my $route_config = shift;

	my $keyData = $self->command([ "HGETALL", $key ]);
	my %result_hash = @{$keyData};

	$self->{logger}->debug("key '$key' loading headers from $result_hash{headers} (" . Dumper(\%result_hash) . ")");

	$keyData = $self->command([ "HGETALL", $result_hash{headers} ]);
	$result_hash{headers} = {@{$keyData}};
	
	if (exists $result_hash{template}) {
		$result_hash{template} = new Text::Template(TYPE => 'STRING', SOURCE => $result_hash{template});
		$result_hash{template}->compile();
	}	

	$$route_config = \%result_hash;
}

sub load_host_triggers {
	my $self = shift;
	my $trigger_key = shift;
	my $host_key = shift;
	my $trigger_config = shift;
	
	my $keyData = $self->command([ "HGETALL", $trigger_key ]);

	my %result_hash = @{$keyData};

	my $load_result = undef;
		
	foreach my $result_key (keys %result_hash) {
		if ($result_hash{$result_key} =~ /^trigger:\/\/[^\/]+\/$/) {
			# This trigger inherits properties from another definition.
			$self->{logger}->debug("host key '$host_key': trigger key '$trigger_key' inheriting from '$result_hash{$result_key}'");
			
			$load_result = $self->load_host_triggers({ -key => $result_hash{$result_key} }, $trigger_config);
		} elsif ($result_hash{$result_key} =~ /^trigger:\/\/[^\/]+\/([^\/]+)\/$/) {
			my $trigger = $1;
		
			# This host inherits properties from another definition.
			$self->{logger}->debug("host key '$host_key': trigger key '$trigger_key' loading trigger '$result_key' from key '$result_hash{$result_key}'");

			if (!$trigger_config->{$result_key}) { $trigger_config->{$result_key} = $result_hash{$result_key}; }
		} else {
			$self->{logger}->warn("host key '$host_key': trigger key '$trigger_key' attempted to load unknown key '$result_hash{$result_key}'");	
		}
	}
		
	return 1;
}

sub load_trigger_definition {
	my $self = shift;
	my $trigger_key = shift;
	my $trigger_config = shift;

	my $keyData = $self->command([ "HGETALL", $trigger_key ]);
	my %trigger_hash = @{$keyData};
		
	$keyData = $self->command([ "HGETALL", $trigger_hash{action} ]);
	$trigger_hash{action} = {@{$keyData}};
		
	$keyData = $self->command([ "HGETALL", $trigger_hash{action}{headers} ]);
	$trigger_hash{action}{headers} = {@{$keyData}};
		
	$trigger_hash{trigger} = new Text::Template(TYPE => 'STRING', SOURCE => $trigger_hash{trigger});
	$trigger_hash{trigger}->compile();
	$trigger_hash{action}{template} = new Text::Template(TYPE => 'STRING', SOURCE => $trigger_hash{action}{template});
	$trigger_hash{action}{template}->compile();
		
	$self->{triggers}{$trigger_key} = \%trigger_hash;	
	
	$$trigger_config = $self->{triggers}{$trigger_key};
	
	return 1;	
}

1;
