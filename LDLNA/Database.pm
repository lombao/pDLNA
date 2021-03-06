package LDLNA::Database;

# Lombix DLNA - a perl DLNA media server
# Copyright (C) 2013 Cesar Lombao <lombao@lombix.com>
#
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2013 Stefan Heumader <stefan@heumader.at>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;
use Encode;

use DBI;

use LDLNA::Config;
use LDLNA::Log;

my %SQL_TABLES;
$SQL_TABLES{SQLITE3} = "SELECT name FROM sqlite_master WHERE type = 'table'";
$SQL_TABLES{MYSQL}   = "SELECT table_name FROM information_schema.tables WHERE table_type = 'base table'";
$SQL_TABLES{PGSQL}   = "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';";

my %SQL_ID_KEYS;
$SQL_ID_KEYS{SQLITE3} = "INTEGER PRIMARY KEY AUTOINCREMENT";
$SQL_ID_KEYS{PGSQL} =   "SERIAL PRIMARY KEY";
$SQL_ID_KEYS{MYSQL} =   "INTEGER auto_increment PRIMARY KEY";




sub connect
{
	my $dbh = undef;
	if ($CONFIG{'DB_TYPE'} eq 'SQLITE3')
	{
		$dbh = DBI->connect('dbi:SQLite:dbname='.$CONFIG{'DB_NAME'},'','') || LDLNA::Log::fatal('Cannot connect: '.$DBI::errstr);
	}
	elsif ($CONFIG{'DB_TYPE'} eq 'PGSQL')
	{
                $dbh = DBI->connect('dbi:Pg:dbname='.$CONFIG{'DB_NAME'},$CONFIG{'DB_USER'},$CONFIG{'DB_PASS'}) || LDLNA::Log::fatal('Cannot connect: '.$DBI::errstr);
	              
	}
	elsif ($CONFIG{'DB_TYPE'} eq 'MYSQL')
	{
                $dbh = DBI->connect('dbi:mysql:dbname='.$CONFIG{'DB_NAME'},$CONFIG{'DB_USER'},$CONFIG{'DB_PASS'}) || LDLNA::Log::fatal('Cannot connect: '.$DBI::errstr);
	} 
	return $dbh;
}

sub disconnect
{
	my $dbh = shift;
	$dbh->disconnect();
}

sub initialize_db
{
	my $dbh = LDLNA::Database::connect();

	my @tables = select_db_tables($dbh);
	if (grep(/^METADATA$/i, @tables))
	{
		my @results = ();
		select_db(
			$dbh,
			{
				'query' => 'SELECT "VALUE" FROM "METADATA" WHERE "KEY" = ?',
				'parameters' => [ 'DBVERSION', ],
			},
			\@results,
		);

		# check if DB was build with a different database version of Lombix DLNA
		if (!defined($results[0]->{VALUE}) || $results[0]->{VALUE} ne $CONFIG{'PROGRAM_DBVERSION'})
		{
			$dbh->do('DELETE FROM "METADATA";');

			insert_db(
				$dbh,
				{
					'query' => 'INSERT INTO "METADATA" ("KEY", "VALUE") VALUES (?,?)',
					'parameters' => [ 'DBVERSION', $CONFIG{'PROGRAM_DBVERSION'}, ],
				},
			);
			insert_db(
				$dbh,
				{
					'query' => 'INSERT INTO "METADATA" ("KEY", "VALUE") VALUES (?,?)',
					'parameters' => [ 'VERSION', LDLNA::Config::print_version(), ],
				},
			);
			insert_db(
				$dbh,
				{
					'query' => 'INSERT INTO "METADATA" ("KEY", "VALUE") VALUES (?,?)',
					'parameters' => [ 'TIMESTAMP', time(), ],
				},
			);

			$dbh->do('DROP TABLE "FILES";') if grep(/^FILES$/, @tables);
			$dbh->do('DROP TABLE "DIRECTORIES";') if grep(/^DIRECTORIES$/, @tables);
			$dbh->do('DROP TABLE "DEVICE_IP";') if grep(/^DEVICE_IP$/, @tables);
			$dbh->do('DROP TABLE "DEVICE_BM";') if grep(/^DEVICE_BM$/, @tables);
			$dbh->do('DROP TABLE "DEVICE_UDN";') if grep(/^DEVICE_UDN$/, @tables);
			$dbh->do('DROP TABLE "DEVICE_NTS";') if grep(/^DEVICE_NTS$/, @tables);
			$dbh->do('DROP TABLE "DEVICE_SERVICE";') if grep(/^DEVICE_SERVICE$/, @tables);
			@tables = ();
		}
	}
	else
	{
		$dbh->do('CREATE TABLE "METADATA" (
				"KEY"				VARCHAR(128) PRIMARY KEY,
				"VALUE"				VARCHAR(128)
			);'
		);

		insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO "METADATA" ("KEY", "VALUE") VALUES (?,?)',
				'parameters' => [ 'DBVERSION', $CONFIG{'PROGRAM_DBVERSION'}, ],
			},
		);
		insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO "METADATA" ("KEY", "VALUE") VALUES (?,?)',
				'parameters' => [ 'VERSION', LDLNA::Config::print_version(), ],
			},
		);
		insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO "METADATA" ("KEY", "VALUE") VALUES (?,?)',
				'parameters' => [ 'TIMESTAMP', time(), ],
			},
		);
	}

	unless (grep(/^FILES$/, @tables))
	{
		$dbh->do('CREATE TABLE "FILES" (
				"ID"				'.$SQL_ID_KEYS{$CONFIG{DB_TYPE}}.',
				"NAME"				VARCHAR(2048),
				"PATH"				VARCHAR(2048),
				"FULLNAME"			VARCHAR(2048),
				"FILE_EXTENSION"	VARCHAR(4),
				"DATE"				BIGINT,
				"SIZE"				BIGINT,
				"MIME_TYPE"			VARCHAR(128) DEFAULT \'unknown\',
				"TYPE"				VARCHAR(12),
				"EXTERNAL"			INTEGER DEFAULT 0,
				"ROOT"				INTEGER,
				"SEQUENCE"			BIGINT,
				"WIDTH"				INTEGER,
				"HEIGHT"			INTEGER,
				"DURATION"			INTEGER DEFAULT 0,
				"BITRATE"			INTEGER DEFAULT 0,
				"VBR"				INTEGER DEFAULT 0,
				"CONTAINER"			VARCHAR(128),
				"AUDIO_CODEC"			VARCHAR(128),
				"VIDEO_CODEC"			VARCHAR(128),
				"ARTIST"			VARCHAR(128),
				"ALBUM"				VARCHAR(128),
				"TITLE"				VARCHAR(128),
				"GENRE"				VARCHAR(128),
				"YEAR"				VARCHAR(4),
				"TRACKNUM"			INTEGER
			);'
		);
	}


	#
	# TABLE DESCRIPTION
	#
	# TYPE
	# 	0		directory
	# 	1		playlist
	unless (grep(/^DIRECTORIES$/, @tables))
	{
		$dbh->do('CREATE TABLE "DIRECTORIES" (
				"ID"				'.$SQL_ID_KEYS{$CONFIG{DB_TYPE}}.',
				"NAME"				VARCHAR(2048),
				"PATH"				VARCHAR(2048),
				"DIRNAME"			VARCHAR(2048)
			);'
		);
	}


	unless (grep(/^DEVICE_IP$/, @tables))
	{
		$dbh->do('CREATE TABLE "DEVICE_IP" (
				"ID"				'.$SQL_ID_KEYS{$CONFIG{DB_TYPE}}.',
				"IP"				VARCHAR(15),
				"USER_AGENT"			VARCHAR(128),
				"LAST_SEEN"			BIGINT
			);'
		);
	}

	unless (grep(/^DEVICE_BM$/, @tables))
	{
		$dbh->do('CREATE TABLE "DEVICE_BM" (
				"ID"				    '.$SQL_ID_KEYS{$CONFIG{DB_TYPE}}.',
				"DEVICE_IP_REF"			INTEGER,
				"FILE_ID_REF"			INTEGER,
				"POS_SECONDS"			INTEGER
			);'
		);
	}

	unless (grep(/^DEVICE_UDN$/, @tables))
	{
		$dbh->do('CREATE TABLE "DEVICE_UDN" (
				"ID"				    '.$SQL_ID_KEYS{$CONFIG{DB_TYPE}}.',
				"DEVICE_IP_REF"			INTEGER,
				"UDN"				VARCHAR(64),
				"SSDP_BANNER"			VARCHAR(256),
				"DESC_URL"		    	VARCHAR(512),
				"RELA_URL"			VARCHAR(512),
				"BASE_URL"			VARCHAR(512),
				"TYPE"				VARCHAR(256),
				"MODEL_NAME"			VARCHAR(256),
				"FRIENDLY_NAME"			VARCHAR(256)
			);'
		);
	}

	unless (grep(/^DEVICE_NTS$/, @tables))
	{
		$dbh->do('CREATE TABLE "DEVICE_NTS" (
				"ID"				        '.$SQL_ID_KEYS{$CONFIG{DB_TYPE}}.',
				"DEVICE_UDN_REF"			INTEGER,
				"TYPE"				        VARCHAR(128),
				"EXPIRE"				BIGINT
			);'
		);
	}

	unless (grep(/^DEVICE_SERVICE$/, @tables))
	{
		$dbh->do('CREATE TABLE "DEVICE_SERVICE" (
				"ID"				    '.$SQL_ID_KEYS{$CONFIG{DB_TYPE}}.',
				"DEVICE_UDN_REF"		INTEGER,
				"SERVICE_ID"			VARCHAR(256),
				"TYPE"				VARCHAR(256),
				"CONTROL_URL"			VARCHAR(512),
				"EVENT_URL"			VARCHAR(512),
				"SCPD_URL"			VARCHAR(512)
			);'
		);
	}


	LDLNA::Database::disconnect($dbh);
}

sub select_db_tables
{
	my $dbh = shift;

	my @tables = ();
    
    
	select_db_array(
		$dbh,
		{
			'query' => $SQL_TABLES{$CONFIG{'DB_TYPE'}},
			'parameters' => [  ],
		},
		\@tables,
	);

	return @tables;
}

sub select_db_array
{
	my $dbh = shift;
	my $params = shift;
	my $result = shift;
	my $starttime = LDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'});
	$sth->execute(@{$$params{'parameters'}}) or die $sth->errstr;
	while (my $data = $sth->fetchrow_array())
	{
		push(@{$result}, $data);
	}

	_log_query($params, $starttime, LDLNA::Utils::get_timestamp_ms());
}

sub select_db_field_int
{
	my $dbh = shift;
	my $params = shift;
	my $starttime = LDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'});
	$sth->execute(@{$$params{'parameters'}}) or die $sth->errstr;
	my $result = $sth->fetchrow_array();

	_log_query($params, $starttime, LDLNA::Utils::get_timestamp_ms());
	return $result || 0;
}

sub select_db
{
	my $dbh = shift;
	my $params = shift;
	my $result = shift;
	my $starttime = LDLNA::Utils::get_timestamp_ms();
    
    my $sth;
	#_log_query($params);
    
    my @sanitized_params;
    foreach my $p (@{$$params{'parameters'}}) {
       push (@sanitized_params, Encode::decode('UTF-8', $p )); # UTF-8 drives me crazy
     }
    
	eval { $sth = $dbh->prepare($$params{'query'}) };  die "Could not prepare Query: ".$$params{'query'}."\n" if ($@);
	$sth->execute(@sanitized_params) or die "Query: ".$$params{'query'}. " with error ==> ". $sth->errstr;
	while (my $data = $sth->fetchrow_hashref)
	{
		push(@{$result}, $data);
	}

	_log_query($params, $starttime, LDLNA::Utils::get_timestamp_ms());
}

sub insert_db
{
	my $dbh = shift;
	my $params = shift;
	my $starttime = LDLNA::Utils::get_timestamp_ms();

    my @sanitized_params;
    foreach my $p (@{$$params{'parameters'}}) {
       push (@sanitized_params, Encode::decode('UTF-8', $p )); # UTF-8 drives me crazy
     }

	my $sth = $dbh->prepare($$params{'query'});
	$sth->execute(@sanitized_params) or die "Query: ".$$params{'query'}. " [  @sanitized_params ]  with error ==> ". $sth->errstr;

	_log_query($params, $starttime, LDLNA::Utils::get_timestamp_ms());
}

sub update_db
{
	my $dbh = shift;
	my $params = shift;
	my $starttime = LDLNA::Utils::get_timestamp_ms();
    
    my @sanitized_params;
    foreach my $p (@{$$params{'parameters'}}) {
       push (@sanitized_params, Encode::decode('UTF-8', $p )); # UTF-8 drives me crazy
     }

	my $sth = $dbh->prepare($$params{'query'});
	$sth->execute(@sanitized_params) or die "Query: ".$$params{'query'}. " [ @sanitized_params ]  with error ==> ". $sth->errstr;
    
	_log_query($params, $starttime, LDLNA::Utils::get_timestamp_ms());
}

sub delete_db
{
	my $dbh = shift;
	my $params = shift;
	my $starttime = LDLNA::Utils::get_timestamp_ms();

    my @sanitized_params;
    foreach my $p (@{$$params{'parameters'}}) {
       push (@sanitized_params, Encode::decode('UTF-8', $p )); # UTF-8 drives me crazy
     }
     
	my $sth = $dbh->prepare($$params{'query'});
	$sth->execute(@sanitized_params) or die $sth->errstr;;

	_log_query($params, $starttime, LDLNA::Utils::get_timestamp_ms());
}

#
# HELPER FUNCTIONS
#

sub _log_query
{
	my $params = shift;
	my $starttime = shift || 0;
	my $endtime = shift || 0;

	my $parameters = '';
	foreach my $param (@{$$params{'parameters'}})
	{
		if (defined($param))
		{
			$parameters .= $param.', ';
		}
		else
		{
			$parameters .= 'undefined, ';
		}
	}
	substr($parameters, -2) = '';

	my $time = $endtime - $starttime;

	LDLNA::Log::log('(Query took '.$time.'ms): '. $$params{'query'}.' - '.$parameters, 1, 'database');
}


#
# Second level of db layer 
# Get records from TABLE where the search clausules are defined
# in a hash ref, the keys are the FIELDS and the values are the lookup values
sub get_records_by
{
 my $table  = shift;
 my $params = shift;
 
        my @setarray;
        my @paramsarray;
        my @records = ();        

        my $sql = 'SELECT * FROM  "'.$table.'"  ';
        if (defined $params)
        {
        $sql = $sql . " WHERE ";
        foreach my $key (keys(%{$params}))
         {
          if (! defined ($$params{$key}) )
           {
            push @setarray , "\"$key\" IS NULL";
           }
          else
           {
            if ( $$params{$key} =~ /%$/ )
             {
              push @setarray , "\"$key\" LIKE ?";
              push @paramsarray, $$params{$key}; 
             }
            else
             {
             push @setarray, "\"$key\" = ?";
             push @paramsarray, $$params{$key};
             }
           } 
        } # end for
        $sql = $sql . join(' AND ',@setarray) ; 
        } # end if
                 
        my $dbh = LDLNA::Database::connect();
        LDLNA::Database::select_db(
             $dbh,
             {
             'query' => $sql,
             'parameters' => \@paramsarray
             },
            \@records
         );
         LDLNA::Database::disconnect($dbh);                  

  return @records;
}



##
## INTERFACE FUNCTIONS FOR OTHER MODULES
## -------------------------------------
## 
## In order to access the database the other modules
## will use any of these
##



##
## FILES TABLE
##



# Given an ID , just delete the entry of that file
sub files_delete
{
 my $file_id = shift;
 
        my $dbh = LDLNA::Database::connect();
        LDLNA::Database::delete_db(
            $dbh,
            {
             'query' => 'DELETE FROM "FILES" WHERE "ID" = ?',
             'parameters' => [ $file_id, ],
            },
        );
        LDLNA::Database::disconnect($dbh);
                                                                                                                 
}


# Update FILES, given an ID , and then an array with a hash ref 
#    where the keys are the names of the fields and the values the values
#    we want to update.   NOTE: undef perl value will be transformed into an ANSI SQL  NULL value. 
sub files_update
{
 my $id  = shift;
 my $params = shift;
 
        my @setarray;
        my @paramsarray;
        
        my $sql = 'UPDATE "FILES" SET ';
        foreach my $key (keys(%{$params}))
         {
          push @setarray, "\"$key\" = ?";
          push @paramsarray, $$params{$key}; 
         }
        $sql = $sql . join(',',@setarray) . " WHERE \"ID\" = ?"; 
        push @paramsarray, $id;
                
        my $dbh = LDLNA::Database::connect();
        LDLNA::Database::update_db(
             $dbh,
             {
             'query' => $sql,
             'parameters' => \@paramsarray
             },
         );
         LDLNA::Database::disconnect($dbh);                  
}


#
sub files_get_all_size
{
  my $type = shift || undef;

        my $dbh = LDLNA::Database::connect();
        my $sql_query = 'SELECT COUNT("ID") AS "AMOUNT", SUM("SIZE") AS "SIZE" FROM "FILES"';
        my @sql_param = ();
        if (defined($type))
        {
                $sql_query .= ' WHERE "TYPE" = ? GROUP BY "TYPE"';
                push(@sql_param, $type);
        }

        my @result = ();
        LDLNA::Database::select_db(
                $dbh,
                {
                        'query' => $sql_query,
                        'parameters' => \@sql_param,
                },
                \@result,
        );
        LDLNA::Database::disconnect($dbh);

   return ($result[0]->{AMOUNT}, $result[0]->{SIZE});
}

sub files_get_all_duration
{
        my $dbh = LDLNA::Database::connect();
        my $duration = LDLNA::Database::select_db_field_int(
                  $dbh,
                  {
                   'query' => 'SELECT SUM("DURATION") AS "SUMDURATION" FROM "FILES"',
                   'parameters' => [ ],
                   },
        );
        LDLNA::Database::disconnect($dbh);

  return $duration;
}

#----
sub files_get_non_external_files
{

        my @files = ();
        my $dbh = LDLNA::Database::connect();
        LDLNA::Database::select_db(
              $dbh,
              {
               'query' => 'SELECT "ID", "FULLNAME" FROM "FILES" WHERE "EXTERNAL" = 0',
               'parameters' => [ ],
               },
              \@files,
        );
        LDLNA::Database::disconnect($dbh);

   return @files;
}

sub files_get_external_files
{

        my @files = ();
        my $dbh = LDLNA::Database::connect();
        LDLNA::Database::select_db(
              $dbh,
              {
               'query' => 'SELECT "ID", "FULLNAME" FROM "FILES" WHERE "EXTERNAL" = 1',
               'parameters' => [ ],
               },
              \@files,
        );
        LDLNA::Database::disconnect($dbh);

   return @files;
}
#----------

  
 
sub files_get_all_valid_records
{
        my @results = ();
        my $dbh = LDLNA::Database::connect();
        LDLNA::Database::select_db(
             $dbh,
             {
             'query' => 'SELECT * FROM "FILES" WHERE "TYPE" is not NULL and "MIME_TYPE" != \'unknown\' and "MIME_TYPE" is not NULL',
             'parameters' => [ ],
             },
             \@results,
        );
        LDLNA::Database::disconnect($dbh);
   
 return @results;

}                                                                                                                                

#------------

# It inserts a new record into files and it returns back a 
# hash ref with the record of that new record that contains the
# assigned ID.
sub files_insert_returning_record
{
 my $params = shift;
 
            my $dbh = LDLNA::Database::connect();                        
            LDLNA::Database::insert_db(
                       $dbh,
                       {
                       'query' => 'INSERT INTO "FILES" ("NAME", "PATH", "FULLNAME", "FILE_EXTENSION", "DATE", "SIZE", "MIME_TYPE", "TYPE", "EXTERNAL", "ROOT", "SEQUENCE") VALUES (?,?,?,?,?,?,?,?,?,?,?)',  
                       'parameters' => [ $$params{'element_basename'}, $$params{'element_dirname'}, $$params{'element'}, $$params{'file_extension'}, $$params{'date'}, $$params{'size'},  $$params{'mime_type'},$$params{'media_type'},$$params{'external'},$$params{'root'},$$params{'sequence'} ],
                       },
            );    

            my @records = get_records_by("FILES", { FULLNAME => $$params{'element'},PATH => $$params{'element_dirname'}});
            LDLNA::Database::disconnect($dbh);
            
       return $records[0];                         
}



sub files_insert
{
 my $element_basename = shift;
 my $element_dirname  = shift;
 my $element          = shift;
 my $file_extension   = shift;
 my $date             = shift;
 my $size             = shift;
 my $mime_type        = shift;
 my $type             = shift;
 my $external         = shift;
 my $root             = shift;
 my $sequence         = shift;
     
           # insert file to db
           my $dbh = LDLNA::Database::connect();
           LDLNA::Database::insert_db(
                     $dbh,
                     {
                     'query' => 'INSERT INTO "FILES" ("NAME", "PATH", "FULLNAME", "FILE_EXTENSION", "DATE", "SIZE", "MIME_TYPE", "TYPE", "EXTERNAL", "ROOT", "SEQUENCE") VALUES (?,?,?,?,?,?,?,?,?,?,?)',  
                     'parameters' => [ $element_basename, $element_dirname, $element, $file_extension, $date, $size,  $mime_type, $type, $external, $root, $sequence, ],
                     },
           );
           LDLNA::Database::disconnect($dbh);                                                                                                                                                                             
}





##
## DEVICE_IP


sub device_ip_delete_by_id
 {
  my $device_ip_id = shift;

        my $dbh = LDLNA::Database::connect();
        LDLNA::Database::delete_db(
                $dbh,
                {
                 'query' => 'DELETE FROM "DEVICE_IP" WHERE "ID" = ?',
                 'parameters' => [ $device_ip_id, ],
                },
        );
       LDLNA::Database::disconnect($dbh);
}

#
# given a database connection and a ip address,
# returns its id
sub device_ip_get_id
{
   my $dbh = shift;
   my $ip = shift;
        
        my $flag = 0;
        if (!defined $ip)              # We only pass one param 
        {                              # when we want this function to make
         $ip = $dbh;                   # its own database connection 
         $dbh = LDLNA::Database::connect();
         $flag = 1;
        }
        
        my @devices = ();
        LDLNA::Database::select_db(
                       $dbh,
                       {
                        'query' => 'SELECT "ID", "IP", "USER_AGENT", "LAST_SEEN"  FROM "DEVICE_IP" WHERE "IP" = ?',
                        'parameters' => [ $ip, ],
                       },
                      \@devices,
                     );
                     
        LDLNA::Database::disconnect($dbh) if $flag;
        return $devices[0];
}


#
# If a new IP address is presented, it updates the last_seen and user agent 
# if possible, if the ip is new, then a new device_ip address is created.
sub  device_ip_touch
{
  my $ip = shift;
  my $useragent = shift;

  my $sql;
  my $params;
  my @result;

        my $dbh = LDLNA::Database::connect();
        my $time = time ();

        my $device_ip =  LDLNA::Database::device_ip_get_id($dbh,$ip); 
        if (!defined($device_ip)) 
         {
           LDLNA::Database::insert_db(
                        $dbh,
                        {
                           'query' => 'INSERT INTO "DEVICE_IP" ("IP") VALUES (?)',
                           'parameters' => [ $ip ],
                        },
                );
           $device_ip =  LDLNA::Database::device_ip_get_id($dbh,$ip); 
         }

        if (defined($useragent)) 
         {
          $sql = 'UPDATE "DEVICE_IP" SET "LAST_SEEN" = ?, "USER_AGENT" = ? WHERE "ID" = ?';
          $params = [ $time,$useragent,$device_ip->{ID} ];
         }
        else
         {
          $sql = 'UPDATE "DEVICE_IP" SET "LAST_SEEN" = ?  WHERE "ID" = ?';
          $params = [ $time,$device_ip->{ID} ];
         }

         LDLNA::Database::update_db(
                     $dbh,
                       {
                        'query' => $sql, 
                        'parameters' => $params
                        },
                );

         LDLNA::Database::disconnect($dbh);
         
         return $device_ip->{ID};
}

##
## DEVICE UDN

sub device_udn_insert
{
  my $device_ip_id = shift;
  my $udn          = shift;
  my $ssdp_banner  = shift;
  my $dev_desc_loc = shift;
  my $dev_udn_base_url = shift;
  my $dev_udn_rela_url = shift;
  my $dev_udn_devicetype = shift;
  my $dev_udn_modelname  = shift;
  my $dev_udn_friendlyname = shift;

        my $dbh = LDLNA::Database::connect();
        LDLNA::Database::insert_db(
                 $dbh,
                  {
           'query' => 'INSERT INTO "DEVICE_UDN" ("DEVICE_IP_REF", "UDN", "SSDP_BANNER", "DESC_URL", "RELA_URL", "BASE_URL", "TYPE", "MODEL_NAME", "FRIENDLY_NAME") VALUES (?,?,?,?,?,?,?,?,?)',
           'parameters' => [ $device_ip_id, $udn, $ssdp_banner, $dev_desc_loc, $dev_udn_base_url, $dev_udn_rela_url, $dev_udn_devicetype, $dev_udn_modelname, $dev_udn_friendlyname, ],
                   },
         );
        LDLNA::Database::disconnect($dbh);

}


sub device_udn_get_modelname
{ 
  my $ip = shift;

        my @modelnames = ();
        my $dbh = LDLNA::Database::connect();
        LDLNA::Database::select_db(
                $dbh,
                {
                  'query' => 'SELECT "ID", "MODEL_NAME" FROM "DEVICE_UDN" WHERE "DEVICE_IP_REF" IN (SELECT "ID" FROM "DEVICE_IP" WHERE "IP" = ?)',
                  'parameters' => [ $ip, ],
                },
                \@modelnames,
        );
        LDLNA::Database::disconnect($dbh);
        return @modelnames;
}

sub device_udn_delete_by_id
{
  my $dbh = shift;
  my $device_udn_id = shift;

        my $flag = 0;
        if (!defined $device_udn_id)   # We only pass one param 
        {                              # when we want this function to make
         $device_udn_id = $dbh;        # its own database connection 
         $dbh = LDLNA::Database::connect();
         $flag = 1;
        }

        LDLNA::Database::delete_db(
                $dbh,
                {
                        'query' => 'DELETE FROM "DEVICE_UDN" WHERE "ID" = ?',
                        'parameters' => [ $device_udn_id, ],
                },
        );

        # delete the DEVICE_SERVICE entries
        LDLNA::Database::device_service_delete($device_udn_id);
        
        LDLNA::Database::disconnect($dbh) if $flag;

}




sub device_udn_delete_without_nts
{

        my $dbh = LDLNA::Database::connect();
        my @device_udn = ();
        LDLNA::Database::select_db(
                $dbh,
                {
                 'query' => 'SELECT "ID" FROM "DEVICE_UDN"',
                 'parameters' => [ ],
                },
                \@device_udn,
        );
        foreach my $udn (@device_udn)
        {
                my @device_nts_amount = LDLNA::Database::device_nts_amount($udn->{ID});
                if ($device_nts_amount[0]->{AMOUNT} == 0)
                {
                       LDLNA::Database::device_udn_delete_by_id($dbh, $udn->{ID});
                }
        }
        LDLNA::Database::disconnect($dbh);

}


sub  device_udn_select_by_ip
{ 
  my $device_ip_id = shift;

                my @devices_udn = ();
                my $dbh = LDLNA::Database::connect();
                LDLNA::Database::select_db(
                        $dbh,
                        {
                                'query' => 'SELECT "ID", "UDN" FROM "DEVICE_UDN" WHERE "DEVICE_IP_REF" = ?',
                                'parameters' => [ $device_ip_id ],
                        },
                        \@devices_udn,
                );
                LDLNA::Database::disconnect($dbh);

       return @devices_udn;
}


##
## DEVICE SERVICE
##
sub device_service_insert
{
  my $device_udn_id = shift;
  my $serviceId     = shift;
  my $serviceType   = shift;
  my $controlURL    = shift;
  my $eventSubURL   = shift;
  my $scpdURL       = shift;

        my $dbh = LDLNA::Database::connect();
        LDLNA::Database::insert_db(
           $dbh,
            {
            'query' => 'INSERT INTO "DEVICE_SERVICE" ("DEVICE_UDN_REF", "SERVICE_ID", "TYPE", "CONTROL_URL", "EVENT_URL", "SCPD_URL") VALUES (?,?,?,?,?,?)',
            'parameters' => [ $device_udn_id, $serviceId, $serviceType, $controlURL, $eventSubURL, $scpdURL ],
             }
        );
       LDLNA::Database::disconnect($dbh);

}


sub device_service_delete
{
   my $dbh           = shift;
   my $device_udn_id = shift;
      
      
             my $flag = 0;
             if (!defined $device_udn_id)       # We only pass one param 
             {                                  # when we want this function to make
              $device_udn_id = $dbh;            # its own database connection
              $dbh = LDLNA::Database::connect();
              $flag = 1;
             }
            LDLNA::Database::delete_db(
            $dbh, 
               {
                    'query' => 'DELETE FROM "DEVICE_SERVICE" WHERE "DEVICE_UDN_REF" = ?',
                        'parameters' => [ $device_udn_id, ],
               },
            );
            LDLNA::Database::disconnect($dbh) if $flag;

}

sub device_service_get_records_by_serviceid
{
 my $service_id = shift;

                my $dbh = LDLNA::Database::connect();
                my @device_services = ();
                LDLNA::Database::select_db(
                      $dbh,
                      {
                       'query' => 'SELECT "TYPE", "CONTROL_URL" FROM "DEVICE_SERVICE" WHERE "SERVICE_ID" = ?', 
                       'parameters' => [ $service_id ],
                      },
                      \@device_services,
                );
                LDLNA::Database::disconnect($dbh);

    return @device_services;
}  



##
## DEVICE NTS
##

sub  device_nts_amount
{
 my $dbh           = shift;
 my $device_udn_id = shift;


        my $flag = 0;
        if (!defined $device_udn_id)   # We only pass one param 
        {                              # when we want this function to make
         $device_udn_id = $dbh;        # its own database connection 
         $dbh = LDLNA::Database::connect();
         $flag = 1;
        }

         my @device_nts_amount = ();
         LDLNA::Database::select_db(
               $dbh,
               {
                'query' => 'SELECT COUNT("ID") AS "AMOUNT" FROM "DEVICE_NTS" WHERE "DEVICE_UDN_REF" = ?',
                'parameters' => [ $device_udn_id ],
                },
               \@device_nts_amount,
         );
         LDLNA::Database::disconnect($dbh) if ($flag);
         return @device_nts_amount;

}


sub device_nts_get_records
{
 my $device_udn_ref = shift;

                my $dbh = LDLNA::Database::connect();

                my @device_nts = ();
                LDLNA::Database::select_db(
                        $dbh,
                        {
                         'query' => 'SELECT "TYPE", "EXPIRE" FROM "DEVICE_NTS" WHERE "DEVICE_UDN_REF" = ?',
                         'parameters' => [ $device_udn_ref ],
                        },
                       \@device_nts,
                );
                LDLNA::Database::disconnect($dbh);

          return @device_nts;
}


sub device_nts_device_udn_ref
{
  my $devicetype = shift;
 
                my @device_udns = (); 
                my $dbh = LDLNA::Database::connect();
                LDLNA::Database::select_db(
                        $dbh,
                        {
                                'query' => 'SELECT "DEVICE_UDN_REF" FROM "DEVICE_NTS" WHERE "TYPE" = ?',
                                'parameters' => [ $devicetype, ],
                        },
                        \@device_udns,
                );
                LDLNA::Database::disconnect($dbh);

                return @device_udns;
}



sub device_nts_get_id
{
   my $dbh = shift;
   my $device_udn_id = shift;  
   my $device_nts_type = shift;


        my $flag = 0;
        if (!defined $device_nts_type)        # We only pass one param 
        {                                     # when we want this function to make
         $device_nts_type = $device_udn_id;   # its own database connection
         $device_udn_id   = $dbh; 
         $dbh = LDLNA::Database::connect();
         $flag = 1;
        }

        my @device_nts = ();
        LDLNA::Database::select_db(
                $dbh,
                {
                        'query' => 'SELECT "ID" FROM "DEVICE_NTS" WHERE "DEVICE_UDN_REF" = ? AND "TYPE" = ?',
                        'parameters' => [ $device_udn_id, $device_nts_type, ],
                },
                \@device_nts,
        );
        LDLNA::Database::disconnect($dbh) if $flag;

        return $device_nts[0]->{ID};
}


sub device_nts_delete 
{
   my $dbh    = shift;
   my $nts_id = shift;


            my $flag = 0;
            if (!defined $nts_id)        # We only pass one param 
            {                                     # when we want this function to make
             $nts_id = $dbh;   # its own database connection
             $dbh = LDLNA::Database::connect();
             $flag = 1;
            }
                                                                    
            LDLNA::Database::delete_db(
            $dbh,
               {
                'query' => 'DELETE FROM "DEVICE_NTS" WHERE "ID" = ?',
                'parameters' => [ $nts_id ],
               },
            );
            LDLNA::Database::disconnect($dbh) if $flag;
}



sub device_nts_touch
{
 my $device_udn_id = shift;
 my $nt            = shift;
 my $nt_time_of_expire = shift;

        my $dbh = LDLNA::Database::connect();
        my $device_nts_id = LDLNA::Database::device_nts_get_id($dbh, $device_udn_id, $nt);
        if (defined($device_nts_id))
        {
                LDLNA::Database::update_db(
                        $dbh,
                        {
                                'query' => 'UPDATE "DEVICE_NTS" SET "EXPIRE" = ? WHERE "ID" = ? AND "TYPE" = ?',
                                'parameters' => [ $nt_time_of_expire, $device_nts_id, $nt ],
                        },
                );
        }
        else
        {
                LDLNA::Database::insert_db(
                        $dbh,
                        {
                                'query' => 'INSERT INTO "DEVICE_NTS" ("DEVICE_UDN_REF", "TYPE", "EXPIRE") VALUES (?,?,?)',
                                'parameters' => [ $device_udn_id, $nt, $nt_time_of_expire ],
                        },
                );
                $device_nts_id = LDLNA::Database::device_nts_get_id($dbh, $device_udn_id, $nt);
        }
       LDLNA::Database::disconnect($dbh);
        
    return  $device_nts_id;
     
}


sub device_nts_delete_expired
{
  my @device_nts = ();

        my $time = time();
        my $dbh = LDLNA::Database::connect();
        LDLNA::Database::select_db(
                $dbh,
                {
                        'query' => 'SELECT "ID", "EXPIRE" FROM "DEVICE_NTS"',
                        'parameters' => [ ],
                },
                \@device_nts,
        );
        foreach my $nts (@device_nts)
        {
                if ($nts->{EXPIRE} < $time)
                {
                  LDLNA::Database::device_nts_delete($dbh,$nts->{ID});
                }
        }
        LDLNA::Database::disconnect($dbh);

}
                 
##
## METADATA
sub metadata_get_value
{
  my $key = shift; 

                 my $dbh = LDLNA::Database::connect();
                 my $val = LDLNA::Database::select_db_field_int(
                     $dbh,
                        {
                        'query' => 'SELECT "VALUE" FROM "METADATA" WHERE "KEY" = ?',
                        'parameters' => [ $key, ],
                        },
                 );
                 LDLNA::Database::disconnect($dbh);


    return $val;
}

sub metadata_update_value
{
     my $value = shift;
     my $key   = shift;
     
            my $dbh = LDLNA::Database::connect();
    		LDLNA::Database::update_db(
			$dbh,
			{
				'query' => 'UPDATE "METADATA" SET "VALUE" = ? WHERE "KEY" = ?',
				'parameters' => [ $value,$key ],
			},
            );
            LDLNA::Database::disconnect($dbh);
}



##
## DEVICE_BM

sub device_bm_get_posseconds
{
    my $item_id      = shift;
    my $device_ip_id = shift;
    
        my $dbh = LDLNA::Database::connect();
	my $bookmark = LDLNA::Database::select_db_field_int(
		$dbh,
		{
		 'query' => 'SELECT "POS_SECONDS" FROM "DEVICE_BM" WHERE "FILE_ID_REF" = ? AND "DEVICE_IP_REF" = ?',
		 'parameters' => [ $item_id, $device_ip_id, ],
		},
		);
                LDLNA::Database::disconnect($dbh);
                
        return $bookmark;
}


sub device_bm_update_posseconds
{
    my $seconds      = shift;
    my $item_id      = shift;
    my $device_ip_id = shift;
    
    
                my $dbh = LDLNA::Database::connect();
				LDLNA::Database::update_db(
					$dbh,
					{
					'query' => 'UPDATE "DEVICE_BM" SET "POS_SECONDS" = ? WHERE "FILE_ID_REF" = ? AND "DEVICE_IP_REF" = ?',
					'parameters' => [ $seconds, $item_id, $device_ip_id, ],
					}
				);
                LDLNA::Database::disconnect($dbh);
            
 
}

sub device_bm_insert_posseconds
{
    my $item_id      = shift;
    my $device_ip_id = shift;
    my $seconds      = shift;
      
                my $dbh = LDLNA::Database::connect(); 
    			LDLNA::Database::insert_db(
                    $dbh,
					{
					'query' => 'INSERT INTO "DEVICE_BM" ("FILE_ID_REF", "DEVICE_IP_REF", "POS_SECONDS") VALUES (?,?,?)',
					'parameters' => [ $item_id, $device_ip_id, $seconds ],
					}
                );
                LDLNA::Database::disconnect($dbh);
                
}

##
## SUBTITLES



sub directories_get_parent
{
     my $object_id = shift;
     
        return 0  if (!defined ($object_id) || $object_id == 0 );
        
        my @directories = ();
        my $dbh = LDLNA::Database::connect();
    	LDLNA::Database::select_db(
            $dbh,
            {
            'query' => 'SELECT "ID" FROM "DIRECTORIES" WHERE "PATH" IN ( SELECT "DIRNAME" FROM "DIRECTORIES" WHERE "ID" = ? );',
            'parameters' => [ $object_id, ],
            },
			\@directories,
		);
        LDLNA::Database::disconnect($dbh);
        
        return 0 if !defined($directories[0]->{ID});
        return $directories[0]->{ID};
    
    
}



sub directories_insert
{
 my $basename_path = shift;
 my $path          = shift;
 my $dirname_path  = shift;
 
 
 
                my $dbh = LDLNA::Database::connect();
                LDLNA::Database::insert_db(
                         $dbh,
                          {
                           'query' => 'INSERT INTO "DIRECTORIES" ("NAME", "PATH", "DIRNAME") VALUES (?,?,?)',
                           'parameters' => [ $basename_path, $path, $dirname_path ],
                          },
                );
                LDLNA::Database::disconnect($dbh);
}


sub directories_delete
{
 my $directory_id = shift;
 
        my $dbh = LDLNA::Database::connect();
        LDLNA::Database::delete_db(
                  $dbh,
                  {
                  'query' => 'DELETE FROM "DIRECTORIES" WHERE "ID" = ?',
                  'parameters' => [ $directory_id, ],
                  },
        );
        LDLNA::Database::disconnect($dbh);
        
                                                                                                                                                                                                                            
}


sub directories_subdirectories_by_id
{
 my $object_id = shift;
 my $starting_index = shift;    
 my $requested_count = shift;   
 my $directory_elements = shift;

        

        my $sql_query;
        my @sql_param;

        if (!defined ($object_id) || $object_id == 0 ) 
        {
          $sql_query = 'select * FROM "DIRECTORIES" WHERE "DIRNAME" not in ( select "PATH" from "DIRECTORIES")';
          @sql_param = ();
        }
        else
        {
         $sql_query = 'SELECT * FROM "DIRECTORIES" WHERE "DIRNAME" IN ( SELECT "PATH" FROM "DIRECTORIES" WHERE "ID" = ? )';
         push(@sql_param, $object_id);
        }

        $sql_query .= ' ORDER BY "NAME"';
        if (defined($starting_index) && defined($requested_count))
        {
            
         if ($CONFIG{DB_TYPE} eq "PGSQL") 
          {
           $sql_query .= ' OFFSET '.$starting_index.' LIMIT '.$requested_count;
        
          }
         else
          {
		   $sql_query .= ' LIMIT '.$starting_index.', '.$requested_count;
          }
	
        }

        my $dbh = LDLNA::Database::connect();
        LDLNA::Database::select_db(
                $dbh,
                {
                        'query' => $sql_query,
                        'parameters' => \@sql_param,
                },
                $directory_elements,
        );

        LDLNA::Database::disconnect($dbh);

}

##########################################

sub get_subfiles_by_id
{
  my $object_id = shift;
  my $starting_index = shift;
  my $requested_count = shift;
  my $file_elements = shift;  


        my $dbh = LDLNA::Database::connect();
        my $sql_query = 'SELECT "ID", "NAME", "SIZE", "DATE" FROM "FILES" WHERE ';
        my @sql_param = ();


        if (!defined ($object_id) || $object_id == 0 ) 
        {
          $sql_query .= '"PATH" NOT IN ( SELECT "PATH" from "DIRECTORIES") or "PATH" is NULL';
        }
        else
        {
          $sql_query .= '"PATH" IN ( SELECT "PATH" FROM "DIRECTORIES" WHERE "ID" = ? )';
          push(@sql_param, $object_id);
        }



        $sql_query .= ' ORDER BY "SEQUENCE", "NAME"';

        if (defined($starting_index) && defined($requested_count))
        {
           if ($CONFIG{DB_TYPE} eq "PGSQL") 
            {
             $sql_query .= ' OFFSET '.$starting_index.' LIMIT '.$requested_count;
            }
           else
            {
		     $sql_query .= ' LIMIT '.$starting_index.', '.$requested_count;
            }
        }

        LDLNA::Database::select_db(
                $dbh,
                {
                        'query' => $sql_query,
                        'parameters' => \@sql_param,
                },
                $file_elements,
        );

      LDLNA::Database::disconnect($dbh);

}

sub get_amount_subfiles_by_id
{
 my $object_id = shift;

        my $dbh = LDLNA::Database::connect();
        my @files_amount = ();

        my $sql_query;
        my @sql_param = ();

        if (!defined ($object_id) || $object_id == 0 ) 
        {
          $sql_query = 'SELECT COUNT("ID") AS "AMOUNT" FROM "FILES" WHERE "PATH" NOT IN ( SELECT "PATH" from "DIRECTORIES")';
        }
        else
        {
          $sql_query = 'SELECT COUNT("ID") AS "AMOUNT" FROM "FILES" WHERE "PATH" IN ( SELECT "PATH" FROM "DIRECTORIES" WHERE "ID" = ?)';
          @sql_param = ( $object_id, );
        }


        LDLNA::Database::select_db(
                $dbh,
                {
                        'query' => $sql_query,
                        'parameters' => \@sql_param,
                },
                \@files_amount,
        );
        LDLNA::Database::disconnect($dbh);

        return $files_amount[0]->{AMOUNT};
}
 
 


sub get_subfiles_size_by_id
{
 my $object_id = shift;

        my $sql_query;
        my @sql_param = ();
        
        if (!defined ($object_id) || $object_id == 0 ) 
        {
          $sql_query = 'SELECT SUM("SIZE") AS "FULLSIZE" FROM "FILES" WHERE "PATH" NOT IN ( SELECT "PATH" from "DIRECTORIES")';
        }
        else
        {
          $sql_query = 'SELECT SUM("SIZE") AS "FULLSIZE" FROM "FILES" WHERE "PATH" IN ( SELECT "PATH" FROM "DIRECTORIES" WHERE "ID" = ? )';
          @sql_param = ( $object_id, );
        }

        my $dbh = LDLNA::Database::connect();
        my @result = ();
        LDLNA::Database::select_db(
                $dbh,
                {
                 'query' => $sql_query,
                 'parameters' => @sql_param,
                },
                \@result,
        );
        LDLNA::Database::disconnect($dbh);
        return $result[0]->{FULLSIZE};
}




sub get_amount_subdirectories_by_id
{
 my $object_id = shift;

        my @directory_amount = ();
        my $dbh = LDLNA::Database::connect();

        my $sql_query = 'SELECT COUNT("ID") AS "AMOUNT" FROM "DIRECTORIES" WHERE ';
        my @sql_param = ();
        
        if (!defined ($object_id) || $object_id == 0 ) 
        {
          $sql_query .= '"DIRNAME" NOT IN ( SELECT "PATH" from "DIRECTORIES")';
        }
        else
        {
         $sql_query .= '"DIRNAME" IN ( SELECT "PATH" FROM "DIRECTORIES" WHERE "ID" = ? )';
         push(@sql_param, $object_id);
        }
        


        LDLNA::Database::select_db(
                $dbh,
                {
                        'query' => $sql_query,
                        'parameters' => \@sql_param,
                },
                \@directory_amount,
        );
        LDLNA::Database::disconnect($dbh);


        return $directory_amount[0]->{AMOUNT};
}


 
sub get_parent_of_item_by_id
{
 my $object_id = shift;

        my $dbh = LDLNA::Database::connect();
        my @item_parent = ();
        LDLNA::Database::select_db(
                $dbh,
                {
                        'query' => 'SELECT "ID" FROM "DIRECTORIES" WHERE "PATH" IN ( SELECT "PATH" FROM "FILES" WHERE "ID" = ? )',
                        'parameters' => [ $object_id, ],
                },
                \@item_parent,
        );
        $item_parent[0]->{ID} = 0 if !defined($item_parent[0]->{ID});
        LDLNA::Database::disconnect($dbh);

        return $item_parent[0]->{ID};
}



####
sub get_amount_elements_by_id
{
 my $object_id = shift;
                
             my $directory_amount = 0;
             $directory_amount += LDLNA::Database::get_amount_subdirectories_by_id( $object_id);
             $directory_amount += LDLNA::Database::get_amount_subfiles_by_id( $object_id);
                                       
         return $directory_amount;
}

##
##

1;
