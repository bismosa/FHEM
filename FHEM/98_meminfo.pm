########################################################################################################################
# $Id: $
#########################################################################################################################
#       meminfo.pm
#
#       (c) 2023 bismosa
#
#       This Module analyzes the data structure in FHEM.
#
#       This script is part of FHEM.
#
#       FHEM is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 2 of the License, or
#       (at your option) any later version.
#
#       FHEM is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with FHEM. If not, see <http://www.gnu.org/licenses/>.
#
#########################################################################################################################
#
# Definition: define <name> meminfo
#
# Example: define mem meminfo
#
# Todo:
#- Doku/Anleitung hinzu/vervollständigen
#- Devel:Size Absturz in Windwos -> Auch auf Linux?

#- Globale Variablen größe?

#- Config auf cam3 und testen!
#- Todos
#- Aufräumen

package main;
use strict;
use warnings;
use Data::Dumper;
use JSON ();
use MIME::Base64 qw(encode_base64 decode_base64);

eval "use Devel::Size qw(size total_size); 1;" ## no critic 'eval'    
    or my $NoDevelSize = "Devel::Size";    

my @meminfo_todolist;
my %meminfo_resulthash;

sub meminfo_test{
	my $str;
	foreach my $variable (sort keys %main::) {
    $str.="$variable\n";
}
return $str;
}

sub meminfo_Initialize {
    my ($hash) = @_;
		
    $hash->{DefFn}   = "meminfo_Define";
    $hash->{UndefFn} = "meminfo_Undef";
    #$hash->{SetFn}   = "meminfo_Set"; #Get benutzen um ein neu Laden der Seite zu verhindern!
		$hash->{GetFn}   = "meminfo_Get";
    $hash->{AttrList} = "disable:1,0 UseDevelSize:1,0 mode:Main,Background,SingleBackground, Output:B,kB,MB IgnoreDevices:textField-long IgnoreDeviceTypes:textField-long";
		$hash->{AttrFn} = "meminfo_Attr";
    return;
}

sub meminfo_Define {
    my ($hash, $def) = @_;
		my $name = $hash->{NAME};
		#Standards setzen, die unbedingt vorhanden sein sollten
    $attr{$name}{UseDevelSize}= '0'            unless (exists($attr{$name}{UseDevelSize}));
		$attr{$name}{Output}= 'kB'            unless (exists($attr{$name}{Output}));
		$attr{$name}{mode}= 'SingleBackground'            unless (exists($attr{$name}{Output}));
		meminfo_checkprereqs($hash);
		return;
}

sub meminfo_checkprereqs {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	$hash->{warnung}="Durch dieses Modul kann FHEM abstürzen! Bitte vorher speichern!";
	delete $hash->{info_ds};
	delete $hash->{info_ds2};
	
	if ($NoDevelSize){
		readingsBeginUpdate($hash);
		#readingsBulkUpdate($hash, "info", "Devel::Size ist nicht installiert! Modul nur eingeschränkt benutzbar" );
		readingsBulkUpdate($hash, "state", "Initialized with error: see internals");
		readingsEndUpdate($hash, 1);
		$hash->{info_ds}="Devel::Size ist nicht installiert! Modul nur eingeschränkt benutzbar";
		$attr{$name}{UseDevelSize}= '0';
	} else {
		my $DevelSizeVersion=eval "use Devel::Size ;Devel::Size->VERSION";
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "state", "Initialized");
		readingsEndUpdate($hash, 1);
		$hash->{info_ds_version}=$DevelSizeVersion;
		if ($DevelSizeVersion <= 0.72){
			$hash->{info_ds}="Devel::Size Version < 0.72. Der Speicherverbrauch könnte sehr hoch sein!";
		}
		if ($attr{$name}{UseDevelSize} == 0){
			$hash->{info_ds2}="UseDevelSize aktivieren um genauere Ergebnisse zu erhalten!";
		}
	}
	meminfo_reloadFW();
}

sub meminfo_reloadFW {
  map { FW_directNotify("#FHEMWEB:$_", "location.reload()", "") } devspec2array("TYPE=FHEMWEB");
}

sub meminfo_Undef {
    my ($hash, $arg) = @_;
    return;
}

sub meminfo_Get {
    my ( $hash, $name, $cmd, @args ) = @_;
		
		Log3 $name, 4, "$name Get $cmd @args";
		
		if ($cmd eq "checkprereqs") {
				meminfo_checkprereqs($hash);
				return;
		}
		
		#################################
		###Dump eines Devices
		if ($cmd eq "Dump_Device") {
			meminfo_blocking_getDeviceHash($hash,$args[0]);
			return;
		}
		if ($cmd eq "Reset_Dump_Device") {
			readingsSingleUpdate($hash, "dump", "-", 1);
			return;
		}
		##Dump eines Devices
		#################################
		
		#################################
		###Analyse
		if ($cmd eq "DeviceInfo") {
			meminfo_Analyze($hash, @args);
			#meminfo_Analyze_Device_ALT($hash, @args);
			return;
    }
		
		if ($cmd eq "TypeInfo") {
			my @selected_devices;
			foreach my $dev(@args){
				push(@selected_devices, devspec2array("TYPE=$dev"));
			}
			#meminfo_Analyze_Device_ALT($hash, @devices);
			meminfo_Analyze($hash, @selected_devices);
			return;
    }

    if ($cmd eq "all") {
			my @devices = devspec2array(".*");
			#meminfo_Analyze_Device_ALT($hash, @devices);
			meminfo_Analyze($hash, @devices);
			return;
		}
		
		if ($cmd eq "(linux)pmap") {
			my $pid = $$;
			my $pmap = qx(pmap $pid);
			readingsSingleUpdate($hash, "Size", $pmap,1);
			return;
		}
		
		if ($cmd eq "RAM_Usage") {
			my $usage=meminfo_getRamUsage();
			readingsSingleUpdate($hash, "RAM", "$usage kB",1);
			return;
		}
		
		if ($cmd eq "WriteDEFtoFiles") {
			meminfo_WriteDef();
			return;
		}
		##Analyse
		#################################
		
		
		#################################
		###Get-Befehle
		#DeviceList
		my @devices = devspec2array(".*");
		@devices = sort @devices;
		
		#Type
		my @types;
		foreach my $d (keys %defs) {
			my $TYPE = $defs{$d}->{TYPE};
			if (!( grep( /^$TYPE$/, @types ) )) {
				push(@types, $TYPE)
			}
		}
		@types = sort (@types);
		
		my $set = "unknown argument $cmd choose one of ";
		
		$set .= "checkprereqs:noArg";
		$set .= " ";
		$set .= "DeviceInfo:" . join(",",@devices);
		$set .= " ";
		$set .= "TypeInfo:" . join(",",@types);
		$set .= " ";
		$set .= "all:noArg";
		$set .= " ";
		$set .= "Dump_Device:" . join(",",@devices);
		$set .= " ";
		$set .= "Reset_Dump_Device:noArg";
		$set .= " ";
		$set .= "(linux)pmap:noArg";
		$set .= " ";
		$set .= "RAM_Usage:noArg";
		$set .= " ";
		$set .= "WriteDEFtoFiles:noArg";
				
		return $set;
		#return "unknown argument $cmd choose one of "  . join(" ", @cList);

}

sub meminfo_Attr($$$$){
	my ( $cmd, $name, $attrName, $attrValue  ) = @_;
	
	#Log3 $name, 4, "[$name] Attr $cmd, $name, $attrName, $attrValue";
	if ($attrName eq "UseDevelSize") {
		my $hash = $defs{$name};
		
		#Prüfen, ob Devel::Size installiert
		if ($NoDevelSize){
				if ($attrValue == 1){
					$attrValue = 0;
					return "Fehler: Devel::Size ist nicht installiert. Attribut kann nicht geändert werden."
				}
		} else {
			if ($attrValue == 1){
				delete $hash->{info_ds2};
			} else {
				$hash->{info_ds2}="UseDevelSize aktivieren um genauere Ergebnisse zu erhalten!";
			}
		}
		
		meminfo_reloadFW();
	}
	
	return undef;
}


#############################################
## Helper

sub meminfo_size {
	my ($name,$size)=@_;
	my $sizemode = $attr{$name}{Output};
	if (not defined $sizemode){
		$sizemode="kB";
	}
	
	if (not defined $size){
		return 0;
	}
	
	if ($sizemode eq "B"){
		return "$size Byte";
	}
	if ($sizemode eq "kB"){
		$size=$size/1024;
		return sprintf("%.2f kB", $size);
		
	}
	if ($sizemode eq "MB"){
		$size=$size/1024/1024;
		return sprintf("%.2f MB", $size);
	}
	
}

sub meminfo_encode { #Base64 + JSON
	my $str = shift;
	#Log3 'mem', 4, "[mem] $str";
	$str = encode_base64($str);
	$str = toJSON($str);
	#Log3 'mem', 4, "[mem] $str";
	return $str;
}

sub meminfo_decode { #from Base64 + JSON
	my $str = shift;
	#Log3 'mem', 4, "[mem] $str";
	$str = JSON->new->decode($str);
	$str = decode_base64($str);
	#Log3 'mem', 4, "[mem] $str";
	return $str;
}

sub meminfo_ignoreDev { #($name $dev) return 1 if ignore
	my ($name, $dev) = @_;
	Log3 $name, 4, "$name Ignore: $dev";
	#Eigenes Device nicht testen!
	if ($dev eq "$name"){
		return 1;
	}
	if ($defs{$dev}->{"TYPE"} eq "meminfo"){
		return 1;
	}
	
	my $a=$attr{$name}{'IgnoreDevices'};
	if (defined $a){
		my @ignoredevs= split("\\,",$a);
		foreach my $id (@ignoredevs){
			if ($id eq $dev){
				return 1;
			}
		}
	}
	
	my $b=$attr{$name}{'IgnoreDeviceTypes'};
	if (defined $b){
		my @ignoredevtypes=split("\\,",$b);
		foreach my $id (@ignoredevtypes){
			if ($defs{$dev}->{"TYPE"} eq "$id"){
				return 1;
			}
		}
	}
	
	
	return 0;
}

sub meminfo_DataStructureSize {
    my ($data, @hashrefs) = @_;
		
		my $size = 0;
		
		#Rekursion vermeiden!
		if (ref($data) eq "HASH") {
			if (meminfo_In_Hashref($data, @hashrefs)){
				Log3 'mem', 4, "[mem] ÜBERSPRINGEN!";
				return $size;
			} else {
				push @hashrefs, $data;
			}
		}
		
		if (ref($data) eq "HASH") {

        foreach my $key (keys %$data) {
						#Log3 'mem', 4, "[mem] DSS HASH $key";
						my $dump = eval {Dumper(\$key)};
						#Log3 'mem', 4, "$dump";
            $size += meminfo_DataStructureSize($data->{$key}, @hashrefs);
        }
    } elsif (ref($data) eq "ARRAY") {
        foreach my $item (@$data) {
						#Log3 'mem', 4, "[mem] DSS ARRAY $item";
            $size += meminfo_DataStructureSize($item, @hashrefs);
        }
    } elsif (ref($data) eq "SCALAR") {
        $size += length($$data);
    } elsif (defined $data) {
        $size += length($data);
    }

    return $size;
}

sub meminfo_In_Hashref { #($testhash, @hashrefs) return 1 if in Hashref
	my ($testhash, @hashrefs) = @_;
	
	if (!(ref($testhash) eq "HASH")) {
		return 0;
	}
	
	foreach my $href (@hashrefs){
		if ($testhash == $href){
			return 1;
		}
	}
}

sub meminfo_DataStructureSizeDevel {
    my ($data) = @_;
		#return total_size(\$data);
		
		my $size2 = eval{use Devel::Size qw(size total_size); $Devel::Size::warn = 0; $Devel::Size::dangle = 0;no warnings; total_size(\$data)};
		#my $size2 = eval{use Devel::Size::Report qw(report_size); my $report=report_size(\$data, {terse => 1 ,head => ''});my @a=split("\\ ",$report);return $a[1]};
		if (!$size2){
			$size2=0;
		}
		return $size2;
		
}

sub meminfo_getRamUsage { #RAM Usage in KB Windows und Linux
	my $pid = $$;
	if ($^O eq 'MSWin32'){
		my $PFU = qx("wmic process where ProcessID=$pid get PageFileUsage");
		my @a=split(/\R/, $PFU);
		return @a[1];
	} else {
		#my $PFU = qx("ps -p $pid -o %rss");
		my $a = "pmap $pid".' | tail -n 1 | awk \'/[0-9]/{print $2}\' | sed \'s/K//g\'';
		my $PFU = qx($a);
		if ($PFU == ""){
			return "Not allowed add 'pmap' to visudo ";
		}
		#return $PFU;
		my @a=split(/\R/, $PFU);
		return @a[0];
	}
}

sub meminfo_WriteDef { #Alle definitionen als RAW in einen Hash und als meminfoDefs.txt speichern
	
	my @types;
	foreach my $d (keys %defs) {
		my $TYPE = $defs{$d}->{TYPE};
		if (!( grep( /^$TYPE$/, @types ) )) {
			push(@types, $TYPE)
		}
	}
	@types = sort (@types);
	
	my %typehash;
	
	foreach my $t(@types){
		next if ($t eq "FHEMWEB");
		next if ($t eq "telnet");
		next if ($t eq "autocreate");
		next if ($t eq "Global");
		
		my $list=fhem("list -r TYPE=$t", 1);
		$typehash{"$t"}{'Name'} = $t;
		$typehash{"$t"}{'List'} = $list;
		
		mkdir("meminfo", 0700) unless(-d "meminfo" );
		open(FH, '>', "meminfo/meminfoDefs_$t.txt") or die $!;
		print FH "$list \n";
		close(FH);
	}
	
	
	
	
	local $Data::Dumper::Terse = 1;
	my $str=meminfo_encode(Dumper(\%typehash));
	
	
	open(FH, '>', 'meminfoDefs.txt') or die $!;
	print FH $str;
	close(FH);
	return "fertig";

}

sub meminfo_createFromDef { #Alle Definitionen aus Text einlesen, jeden Typen wiederherstellen und Memory protokollieren - Nicht fertig!
	
	my @files = glob( "meminfo" . '/*.txt' );
	my %sizehash;
	
	my $lastsize=meminfo_getRamUsage();
	$sizehash{"Start"}{'Name'} = "Start";
	$sizehash{"Start"}{'Size'} = "$lastsize";
	$sizehash{"Start"}{'Diff'} = 0;
	
	my $retval="";
	foreach my $file(@files){
		open my $fh, '<', $file or die "error opening file: $!";
		my $data = do { local $/; <$fh> };
		my @lines=split( "\\\n", $data );
		foreach my $line(@lines){
			$retval .= fhem("$data",1);
			$retval .= " ( $line ) ";
			$retval .="\n";
		}
		
		my $size=meminfo_getRamUsage();
		$sizehash{"$file"}{'Name'} = "$file";
		$sizehash{"$file"}{'Size'} = "$size";
		$sizehash{"$file"}{'Diff'} = $size-$lastsize;
		$lastsize=$size;
	}
	
	#return Dumper(\%sizehash);
	
	
	return $retval;
	
	#open my $fh, '<', 'meminfoDefs.txt' or die "error opening 'meminfoDefs.txt': $!";
	#my $data = do { local $/; <$fh> };
	#my $str=meminfo_decode($data);
	#my %typehash=$str;
	
	#return Dumper(\%typehash);
	#return $str;
	
	#TODO
	#- Speichern als Objekt in Datei
	#- Laden aus Datei
	#- Leeres FHEM starten
	#- Gerätegruppen einzeln wiederherstellen -> Speicher protokollieren
	#- 
	
}

## Helper
#############################################

#############################################
## Device Hash

sub meminfo_blocking_getDeviceHash{
	my ($hash, $device) = @_;
	my $name = $hash->{NAME};
	
	
	#Eigene Devices können nicht analysiert werden!
	if (meminfo_ignoreDev($name, $device)){
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "state", "error" );
		readingsBulkUpdate($hash, "dump", "Device oder Devicetyp kann nicht analysiert werden");
		readingsEndUpdate($hash, 1);
		return;
	}
	
	readingsSingleUpdate($hash, "state", "get Devicve Hash from $device", 1);
	my $timeout    = 10;
	my $arg        = $name."|".$device;
	my $blockingFn = "meminfo_blocking_getDeviceHash_Start";
	my $finishFn   = "meminfo_blocking_getDeviceHash_finish";
	my $abortFn    = "meminfo_blocking_getDeviceHash_abort";
	$hash->{helper}{RUNNING_PID} = BlockingCall( $blockingFn, $arg, $finishFn, $timeout, $abortFn, $hash );
  $hash->{helper}{RUNNING_PID}{loglevel} = 2;
}
sub meminfo_blocking_getDeviceHash_Start{ #als Base64!
	my ($string) = @_;
	my ( $name, $device ) = split( "\\|", $string );
	my $hash = $defs{$name};
	
	my $DumpHash=$defs{$device};
	my $dump = eval {Dumper(\$DumpHash)};
	if (!$dump){
		$dump="error";
	}
	$dump =~ s/\n/<br>/g;
	
	my $retVal="$name|$dump";
	return (meminfo_encode($retVal));
	#my $jsonString = toJSON($dump);
  #return $jsonString;
	#my $encoded=encode_base64($dump);
	#return $encoded;
	#return "$name|$dump";
}
sub meminfo_blocking_getDeviceHash_finish{
	my ($string) = @_;
	$string = meminfo_decode($string);
	my ($name,$dump) = split("\\|", $string, 2);
	$dump =~ s/<br>/\n/g;
	my $hash = $defs{$name};
	
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "state", "ok" );
	readingsBulkUpdate($hash, "dump", $dump);
	readingsEndUpdate($hash, 1);
}
sub meminfo_blocking_getDeviceHash_abort{
	my ($hash) = @_;
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "state", "error get Device hash" );
	readingsEndUpdate($hash, 1);
}

##Device Hash
#############################################

#############################################
## Analyze Devices
sub meminfo_Analyze_BlockingCall{ #($name,$mode) Starten eines Blocking Calls
	my ($name,$mode)=@_;
	Log3 $name, 4, "$name meminfo_Analyze_BlockingCall @meminfo_todolist";
	my $hash = $defs{$name};
	if (@meminfo_todolist == 0){
		return;
	}
	
	if ($mode eq "SingleBackground"){
		my $dev = $meminfo_todolist[0];
		splice @meminfo_todolist, 0, 1;
	
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "state", "start $dev" );
		readingsBulkUpdate($hash, "todo", @meminfo_todolist );	
		readingsEndUpdate($hash, 1);
	
		my $timeout    = 10;
		my $arg        = $name."|$mode|".$dev;
		my $blockingFn = "meminfo_blocking_Analyze_Start";
		my $finishFn   = "meminfo_blocking_Analyze_finish";
		my $abortFn    = "meminfo_blocking_Analyze_abort";
		$hash->{helper}{RUNNING_PID} = BlockingCall( $blockingFn, $arg, $finishFn, $timeout, $abortFn, $hash );
	} else {
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, "state", "start" );
		readingsBulkUpdate($hash, "todo", @meminfo_todolist );	
		readingsEndUpdate($hash, 1);
	
		my $timeout    = 10*60;
		my $arg        = $name."|$mode|"."TODO";
		my $blockingFn = "meminfo_blocking_Analyze_single_Start";
		my $finishFn   = "meminfo_blocking_Analyze_single_finish";
		my $abortFn    = "meminfo_blocking_Analyze_single_abort";
		$hash->{helper}{RUNNING_PID} = BlockingCall( $blockingFn, $arg, $finishFn, $timeout, $abortFn, $hash );
	}
	
}

sub meminfo_Analyze {
	my ($hash, @devices) = @_;
	my $name = $hash->{NAME};
	
	Log3 $name, 4, "[$name] Analysiere @devices";
	
	@meminfo_todolist = (); 
	%meminfo_resulthash = ();
	
	foreach my $dev(@devices){
		if (meminfo_ignoreDev($name, $dev)){
			Log3 $name, 4, "[$name] Überspringe $dev";
			next;
		}
		Log3 $name, 4, "[$name] Füge $dev zur Liste hinzu";
		push(@meminfo_todolist, $dev);
	}
		
	my $mode = $attr{$name}{mode};
	if (not defined $mode){
		$mode="SingleBackground";
	}
	Log3 $name, 4, "[$name] Mode: $mode";
	if ($mode eq "Main"){
		#Ohne BlockingCall
		foreach my $dev(@meminfo_todolist){
			Log3 $name, 4, "$name meminfo_Analyze $dev";
			my $values=meminfo_blocking_Analyze_Start("$name|Main|$dev"); #Ausgabe als Base64!
			if (not defined $values){
				next;
			}
			meminfo_blocking_Analyze_finish($values);
		}
		return;
	}
	if ($mode eq "Background"){
		#mit nur einem BlockingCall
		meminfo_Analyze_BlockingCall($name,$mode);
		return;
	}
	if ($mode eq "SingleBackground"){
		#mit BlockingCall
		meminfo_Analyze_BlockingCall($name,$mode);
		return;
	}
	
	
	return;
	
	
	
		
	
	
	readingsSingleUpdate($hash, "todo", @meminfo_todolist, 1);
	my $dev = ""; #???????????
	my $timeout    = 10;
	my $arg        = $name."|".$dev;
	my $blockingFn = "meminfo_blocking_DeviceInfo_ALT_Start";
	my $finishFn   = "meminfo_blocking_DeviceInfo_ALT_finish";
	my $abortFn    = "meminfo_blocking_DeviceInfo_ALT_abort";

	$hash->{helper}{RUNNING_PID} = BlockingCall( $blockingFn, $arg, $finishFn, $timeout, $abortFn, $hash );
  #$hash->{helper}{RUNNING_PID}{loglevel} = 1;
		
}

sub meminfo_blocking_Analyze_Start{ #String:($name|$mode|$dev)  return: encoded! String: $name|$dev|$mode|$size|$sizeDevel)
	my ($string) = @_;
  my ( $name,$mode, $dev ) = split( "\\|", $string );
	my $hash = $defs{$name};
	
	Log3 $name, 4, "$name Analysiere: $dev";
	
	my $analyzeHash = $defs{$dev};
	
	#Eigenes Device nicht testen! #Wird bereits vorher gefiltert!
	if (meminfo_ignoreDev($name, $dev)){
		return undef;
	}

	#my $log = eval {Dumper(\$analyzeHash)};
	#Log3 $name, 4, "$log";
	#$meminfo_DataStructureSize_hashref=();
	my $size=eval{meminfo_DataStructureSize($analyzeHash)};
	if (not defined $size){
		$size=0;
	}
	if ($size eq ""){
		$size=0;
	}
	
	my $sizeDevel=0;
	if ($attr{$name}{UseDevelSize} == 1){
			$sizeDevel=eval{meminfo_DataStructureSizeDevel($analyzeHash)};
	}
	
	#sleep(1);
	Log3 $name, 4, "$name Size1: $size Size2: $sizeDevel";
	my $returnVal     = "$name|$mode|$dev|$size|$sizeDevel";
	return (meminfo_encode($returnVal));
	#my $jsonString = toJSON($returnVal);
	#return $jsonString;
	#my $encoded = encode_base64($returnVal);
	#return $encoded;
}
sub meminfo_blocking_Analyze_finish{ #encoded! String: $name|$mode|$dev|$size|$sizeDevel
	my ($string) = @_;
	$string = meminfo_decode($string);
	my ( $name,$mode,$dev, $size, $sizeDevel ) = split( "\\|", $string );
	my $hash = $defs{$name};
	
	Log3 $name, 4, "$name meminfo_blocking_Analyze_finish $string";
	
	#Resulthash bilden:
	#$meminfo_resulthash{"$dev"};
	$meminfo_resulthash{"$dev"}{'Name'} = $dev;
	$meminfo_resulthash{"$dev"}{'Size'} = $size;
	$meminfo_resulthash{'sum'}{'SizeDevel'} += $sizeDevel;
	$meminfo_resulthash{'sum'}{'Size'} += $size;
	if ($attr{$name}{UseDevelSize} == 1){
		$meminfo_resulthash{"$dev"}{SizeDevel} = $sizeDevel;
	} else {
		#$meminfo_resulthash{'sum'} += $size;
	}
	
	#my $dump2 = eval {Dumper(\%meminfo_resulthash)};
	#readingsSingleUpdate($hash, "debug2", $dump2,1);
	#Log3 $name, 4, "$name meminfo_blocking_Analyze_finish - fertig";
	
	#Sortieren
	#Auf eine länge bringen:
	my $maxlength=0;
	foreach my $name (keys %meminfo_resulthash){
		$maxlength = length($name) if length($name)>$maxlength;
	}
	
	my $Ausgabe="";
	if ($attr{$name}{UseDevelSize} == 1){
		$Ausgabe=sprintf("%-".$maxlength."s\t","Name");
		$Ausgabe.="SizeDevel (Size content) \n";
		foreach my $name (reverse sort { $meminfo_resulthash{$a}{'SizeDevel'} <=> $meminfo_resulthash{$b}{'SizeDevel'} } keys %meminfo_resulthash) {
			#printf "%-8s %s\n", $name, $meminfo_resulthash{$name}{'Size'};
			$Ausgabe.=sprintf("%-".$maxlength."s\t",$name);
			$Ausgabe.=meminfo_size($name,$meminfo_resulthash{$name}{'SizeDevel'})." (".meminfo_size($name,$meminfo_resulthash{$name}{'Size'}).")\n";
			#$Ausgabe.="$name=\t\t\t".meminfo_size($name,$meminfo_resulthash{$name}{'Size'})."\n";
		}
	} else {
		$Ausgabe=sprintf("%-".$maxlength."s\t","Name");
		$Ausgabe.="Size content\n";
		foreach my $name (reverse sort { $meminfo_resulthash{$a}{'Size'} <=> $meminfo_resulthash{$b}{'Size'} } keys %meminfo_resulthash) {
			#printf "%-8s %s\n", $name, $meminfo_resulthash{$name}{'Size'};
			$Ausgabe.=sprintf("%-".$maxlength."s\t",$name);
			$Ausgabe.=meminfo_size($name,$meminfo_resulthash{$name}{'Size'})."\n";
			#$Ausgabe.="$name=\t\t\t".meminfo_size($name,$meminfo_resulthash{$name}{'Size'})."\n";
		}
	}
	
	#Ausgabe
	readingsSingleUpdate($hash, "Size", $Ausgabe,1);
	
	#mode SingleBackground
	if ($mode eq "SingleBackground"){
		meminfo_Analyze_BlockingCall($name,$mode);
	}
}
sub meminfo_blocking_Analyze_abort{
	my ($hash) = @_;
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "state", "error analyze Device" );
	readingsEndUpdate($hash, 1);
}

##Alle mit einem BlockingCall einlesen
sub meminfo_blocking_Analyze_single_Start{
	my ($string) = @_;
  my ( $name,$mode, @devs ) = split( "\\|", $string );
	my $hash = $defs{$name};
	
	foreach my $dev (@meminfo_todolist){
		my $values=meminfo_blocking_Analyze_Start("$name|Main|$dev"); #Ausgabe als Base64!
		if (not defined $values){
			next;
		}
		meminfo_blocking_Analyze_finish($values);
	}
	my $value = ReadingsVal($name, "Size", "err");
	return (meminfo_encode("$name|$value"));
	
}
sub meminfo_blocking_Analyze_single_finish{
	my ($string) = @_;
	$string = meminfo_decode($string);
	my ( $name,$value ) = split( "\\|", $string );
	my $hash = $defs{$name};
	readingsSingleUpdate($hash, "Size", $value,1);
}
sub meminfo_blocking_Analyze_single_abort{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	readingsSingleUpdate($hash, "Size", "Error",1);
	my $value = ReadingsVal($name, "Size", "err");
	readingsSingleUpdate($hash, "Size", "$value",1);
	
}

## Analyze Devices
#############################################

1;

=pod
=item helper
=item summary	Analyze mem usage from devices
=item summary_DE Analysieren der Speichernutzung von Geräten
=begin html

<a name="meminfo"></a>
<h3>meminfo</h3>

Only German

=end html
=begin html_DE

<a name="meminfo"></a>
<h3>meminfo</h3>

Analysieren der Speichernutzung von Geräten in FHEM<br><br>

<a name="meminfo_define"></a>
<h4>Define</h4>
<ul>
  <code><b><font size="+1">define &lt;name&gt; meminfo</font></b></code>
</ul>

 <a name="meminfo_set"></a>
  <h4>Get </h4>
  <ul>
    <code><b><font size="+1">set &lt;name&gt; &lt;value&gt;</font></b></code>
    <br><br>
    wobei <code>value</code> einer der folgenden ist:<br>
    <pre>
		<li><a name="DeviceInfo">DeviceInfo</a>: Größe von einem Device</li>
		<li><a name="TypeInfo">TypeInfo</a>: Größe aller Devices von einem bestimmten Gerätetyp</li>
		<li><a name="all">all</a>: Größe aller Geräte</li>
		<li><a name="checkprereqs">checkprereqs</a>: Prüft, ob alle Vorraussetzungen gegeben sind</li>
		<li><a name="RAM_Usage">RAM_Usage</a>: Größe des aktuell verwendeten RAMs in ein Reading schreiben</li>
		<li><a name="(linux)pmap">(linux)pmap</a>: MAP der Speicherbelegung (nur unter Linux!) in ein Reading sschreiben.</li>
		<li><a name="WriteDEFtoFiles">WriteDEFtoFiles</a>: Schreibt für jeden Gerätetyp eine Textdatei mit den Definitionen<br>Zu finden in dem Verzeichnis "meminfo"</li>
		<li><a name="Dump_Device">Dump_Device</a>: erzeugt ein reading (dump) mit dem hash-Inhalt eines gewählten Gerätes</li>
		<li><a name="Reset_Dump_Device">Reset_Dump_Device</a>: setzt das reading 'dump' zurück ("-")</li>
    </pre>
  </ul>

  <a name="meminfo_set"></a>
  <h4>Set </h4>
  <ul>
    <li>Derzeit gibt es keine set Befehle für dieses Modul</li>
  </ul>
	
	<a name="meminfo_attr"></a>
  <h4>Attribute</h4>
  <ul>
				<li><a name="UseDevelSize">UseDevelSize</a>: Devel::Size nicht benutzen<br>Nur die größe des Inhalts bestimmen.<br>Devel::Size benötigt viel Speicher. Sollte dieser nicht ausreichen, könnte FHEM abstürzen!</li>
				<li><a name="mode">mode</a>: 
								<br><b>Main</b>: Fhem blockiert während der Ausführung (Vorteil: weniger Speicherbedarf)
								<br><b>Background</b>: Alle Aufgaben werden über einen blockingCall ausgeführt. Fhem ist wärenddessen erreichbar. Der Speicherbedarf von FHEM ist für die Ausführung größer 
								<br><b>SingeBackground</b>: Alle Aufgaben werden über einen blockingCall ausgeführt. Fhem ist wärenddessen erreichbar. Nach jedem Gerät wird der Status aktualisiert.
				</li>
				<li><a name="IgnoreDevices">IgnoreDevices</a>: Kommagetrennte Liste an Geräten, die nicht eingelesen werden </li>
				<li><a name="IgnoreDeviceTypes">IgnoreDeviceTypes</a>: Kommagetrennte Liste an Gerätetypen, die nicht eingelesen werden </li>
				<li><a name="Output">Output</a>: Anzeigeeinheit</li>
  </ul>

=end html_DE

=cut
