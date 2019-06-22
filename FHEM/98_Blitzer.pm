#######################################################################################################################################################
# $Id: 98_Blitzer.pm 22.06.2019 09:30
# 
# Modulversion der Anleitung "Blitzer anzeigen"
# https://forum.fhem.de/index.php/topic,90014.0.html
# 
# Dieses Modul such anhand der Koordinaten die aktuellen Blitzerdaten von www.verkehrslage.de heraus und erstellt einen Text, der in FTUI dargestellt werden kann
# Dies ist nur zu demonstrationszwecken gedacht. Bitte die Bedingungen von www.verkehrslage.de beachten!
# 
# Das Modul JSON wird benötigt!
#
#######################################################################################################################################################
# !!! ToDo´s !!!
#- Map aktivieren - uncaught reference error
#- Map als Bild für Pushnachtrichten
#######################################################################################################################################################
#Special Thanks:
#@inoma Danke für die englische Übersetzung der Commandref! 
#
#
#######################################################################################################################################################

package main;

# Laden evtl. abhängiger Perl- bzw. FHEM-Hilfsmodule
use strict;
use warnings;
use POSIX;
use List::Util qw(any);				# for any function
use Data::Dumper qw (Dumper);
use JSON qw( decode_json );     # From CPAN
#use JSON::XS qw( decode_json );

my %sets = (
	"Voreinstellung_Ausgabe"     => "",
	"_SetDemoValues"     => "noArg",
	"_Berechne_area"     => "noArg",
	"Update"      => "textField"
	#"update"     => "noArg",
);


my %VoreinstellungenStandards = (
	"Stadt" => "number,{OR,suburb,city_district,city,town,village,},building,[Max.],vmax,[km/h],[(],distanceShort,[km],[)],[!!],newline",
	"Stadt2" => "number,suburb,city_district,city,town,village,building,[Max.],vmax,[km/h],[(],distanceShort,[km],[)],[!!],newline",
	"Land" => "number,{OR,suburb,city_district,town,village,},road,building,[Max.],vmax,[km/h],[(],distanceShort,[km],[)],[!!],newline",
	"Land2" => "number,suburb,city_district,town,village,road,building,[Max.],vmax,[km/h],[(],distanceShort,[km],[)],[!!],newline",
	"Sprachausgabe" => "[In],{OR,suburb,city_district,town,village,},[an der],road,building,vmax,[km/h],newline",
);

my @BlitzerPOIS;

my @Werte=("display_name","house_number","road","suburb","city_district","city","postcode","country","country_code","town","village","building");
my @WerteVL=("backend","confirm_date","content","counter","create_date","distance","distanceShort","gps_status","id","info","lat","lat_s","lng","lng_s","polyline","street","type","vmax","MapLink");

#####################################
sub Blitzer_Initialize() {
	my ($hash) = @_;
	$hash->{DefFn}		= "Blitzer_Define";
	$hash->{UndefFn}	= "Blitzer_Undef";
	$hash->{AttrFn}		= "Blitzer_Attr";
	$hash->{SetFn}		= "Blitzer_Set";
	$hash->{GetFn}      = "Blitzer_Get";
	#$hash->{ParseFn}	= "Blitzer_Parse";
	$hash->{AttrList}	= "Ausgabe:sortable,".join(",",@Werte).join(",",@WerteVL).",number,newline,newline,[(],[)],[Max.],[km/h],[km],[!!],[],{OR,} "	
						."radius home_latitude home_longitude area_bottomLeft_latitude area_bottomLeft_longitude area_topRight_latitude area_topRight_longitude "
						."createAllReadings:0,1 "
						."createUpdateReading:0,1 "
						."httpGetTimeout "
						."createNoHTML:0,1 "
						."DontUseOSM:0,1 "
						."HTML_Before HTML_After HTML_Without Text_Without "
						."DontUseOSM:0,1 "
						."disable:0,1 "
						."MaxSpeedCameras "
						."createCountReading:0,1 "
						."MapWidth MapHeight MapShow:0,1 "
						."ShowFixed:0,1 "
						.$readingFnAttributes;
  $hash->{FW_summaryFn}	= "Blitzer_summaryFn";          # displays html instead of status icon in fhemweb room-view
}

#####################################
sub Blitzer_Define() {
	my ($hash, $def) = @_;
	my $name = $hash->{NAME};
	
	my @a = split("[ \t][ \t]*", $def);
	Log3 $name, 4, "Blitzer: Anzahl Argumente = ".int(@a);
	Log3 $name, 4, "Blitzer: Argument0 = ".$a[0] if(int(@a) > 0);
	Log3 $name, 4, "Blitzer: Argument1 = ".$a[1] if(int(@a) > 1);
	Log3 $name, 4, "Blitzer: Argument2 = ".$a[2] if(int(@a) > 2);
	Log3 $name, 4, "Blitzer: Argument3 = ".$a[3] if(int(@a) > 3);
	# Argument            				   0	     1      
	return " wrong syntax: define <name> Blitzer Optional:<Interval>" if(int(@a) < 2 || int(@a) > 3);
	
	if (int(@a) == 3) {
		$hash->{refreshIntervall} = $a[2];
	} else {
		$hash->{refreshIntervall} = 0;
		$hash->{DEF} = 0;
	}
	
	if ($init_done == 1){
		#Log3 $name, 1, "Blitzer: not defined";
		#nur beim ersten define setzen:
		$attr{$name}{icon} = "message_attention" if( not defined( $attr{$name}{icon} ) );
		$attr{$name}{room} = "Blitzer" if( not defined( $attr{$name}{room} ) );
	} else {
		#Log3 $name, 1, "Blitzer: already defined";
	}
	 
	$hash->{STATE} = "Defined";
	#$modules{Blitzer}{defptr}{$hash->{DEF}} = $hash;
	
	# Standards setzen 
	$attr{$name}{radius} = "10" if( not defined( $attr{$name}{radius} ) );
	$attr{$name}{Ausgabe} = $VoreinstellungenStandards{Stadt} if( not defined( $attr{$name}{Ausgabe} ) );
	$attr{$name}{createAllReadings} = "0" if( not defined( $attr{$name}{createAllReadings} ) );
	$attr{$name}{createNoHTML} = "0" if( not defined( $attr{$name}{createNoHTML} ) );
	$attr{$name}{createUpdateReading} = "1" if( not defined( $attr{$name}{createUpdateReading} ) );
	$attr{$name}{HTML_Before} = "<html> <p align='left'>Aktuelle Blitzer:<br>" if( not defined( $attr{$name}{HTML_Before} ) );
	$attr{$name}{HTML_Without} = "<html> <p align='left'>Keine Blitzer in der Nähe</p></html>" if( not defined( $attr{$name}{HTML_Without} ) );
	
	Blitzer_SetTimer($hash);
	return undef;
}

#####################################
sub Blitzer_Undef($$) {
	my ($hash, $name) = @_;
	delete($modules{Blitzer}{defptr}{$hash->{DEF}}) if(defined($hash->{DEF}) && defined($modules{Blitzer}{defptr}{$hash->{DEF}}));
	return undef;
}

#####################################
sub Blitzer_Attr(@) {
	my ($cmd, $name, $attrName, $attrValue) = @_;
	my $hash = $defs{$name};
	
	if ($init_done == 1) {
		if ($cmd eq "set") {
			
			#Prüfen, ob OR richtig gesetzt wurde
			if ($attrName eq "Ausgabe"){
				my $countStart = () = $attrValue =~ /{/g;
				my $countEnd = () = $attrValue =~ /}/g;
				if ($countStart != $countEnd){
					return "Error: You must close all '{'";
				}
			}
			
			##area automatisch setzen, wenn Vorraussetzungen erfüllt sind:
			if (defined($attr{$name}{home_latitude}) && defined($attr{$name}{home_longitude}) && defined($attr{$name}{radius})){
				if ((not defined($attr{$name}{area_bottomLeft_latitude})) && (not defined($attr{$name}{area_bottomLeft_longitude})) && 
								(not defined($attr{$name}{area_topRight_latitude})) && (not defined($attr{$name}{area_topRight_longitude}))){
					Blitzer_SetArea($hash);
				}
			}
		}
		
		##disabled?
		if ($attrName eq "disable"){
			my $disabled = $attrValue;
			$disabled = 0 if (not defined $attrValue);
			if ($disabled == 1){
				Blitzer_DelTimer($hash);
			} else {
				#hash setzen!
				$attr{$name}{disable} = 0;
				Blitzer_Update($hash, undef, undef, undef);
			}
		}
		
		if ($cmd eq "del") {
			
		}

		Log3 $name, 4, "Blitzer: $cmd attr $attrName to $attrValue" if (defined $attrValue);
		Log3 $name, 4, "Blitzer: $cmd attr $attrName" if (not defined $attrValue);
	}

	return undef;
}

#####################################
sub Blitzer_Set($$$@) {
	my ( $hash, $name, @a ) = @_;
	my $cmd = $a[0];
	my $cmd2 = $a[1];
	my $cmd3 = $a[2]; #Für neue Koordinaten
	my $cmd4 = $a[3]; #Radius
  
	if ( !defined( $sets{$cmd} )) {
		
		#Ausgaben hinzufügen
		my $standardSets="Voreinstellung_Ausgabe:";
		foreach my $standard ( keys %VoreinstellungenStandards ) {
			$standardSets .= $standard.",";
		}
		chop($standardSets); #letztes Zeichen entfernen
		
		#alle anderen hinzufügen
		my $param = "";
		foreach my $val ( keys %sets ) {
			if ($val eq "Voreinstellung_Ausgabe"){
				$param  .= " $standardSets";
			} else {
				$param  .= " $val:$sets{$val}";
			}
		}

        Log3 $name, 4, "ERROR: Unknown command $cmd, choose one of $param" if ( $cmd ne "?" );
        return "Unknown argument $cmd, choose one of $param";
	}
  
	Log3 $name, 4, "Blitzer: cmd1 = $cmd";
	Log3 $name, 4, "Blitzer: cmd2 = $cmd2" if(defined ($cmd2));
	Log3 $name, 4, "Blitzer: cmd3 = $cmd3" if(defined ($cmd3));
	Log3 $name, 4, "Blitzer: cmd4 = $cmd4" if(defined ($cmd4));
	
	if ($cmd eq "Voreinstellung_Ausgabe"){
		$attr{$name}{Ausgabe}=$VoreinstellungenStandards{$cmd2};
		return;
	}
	
	if ($cmd eq "Update"){
		Blitzer_Update($hash,$cmd2,$cmd3,$cmd4);
		Blitzer_CreateMap($hash);
		return;
	}
	
	if ($cmd eq "_SetDemoValues"){
		$attr{$name}{home_latitude} = "52.518061" if( not defined( $attr{$name}{home_latitude} ) );
		$attr{$name}{home_longitude} = "13.403622" if( not defined( $attr{$name}{home_longitude} ) );
		$attr{$name}{area_bottomLeft_latitude} = "52.417522" if( not defined( $attr{$name}{area_bottomLeft_latitude} ) );
		$attr{$name}{area_bottomLeft_longitude} = "13.203419" if( not defined( $attr{$name}{area_bottomLeft_longitude} ) );
		$attr{$name}{area_topRight_latitude} = "52.595944" if( not defined( $attr{$name}{area_topRight_latitude} ) );
		$attr{$name}{area_topRight_longitude} = "13.575818" if( not defined( $attr{$name}{area_topRight_longitude} ) );
		return;
	}
	
	if ($cmd eq "_Berechne_area"){
		Blitzer_SetArea($hash);
		return;
	}
	return $cmd." ".$cmd2;		# to display cmd is running	
}

###################################
sub Blitzer_Get($$@){
	my ( $hash, $name, $opt, @args ) = @_;

	return "\"get $name\" needs at least one argument" unless(defined($opt));
	use Scalar::Util qw(looks_like_number);
	
	if($opt eq "allReadings") 
	{
		#return Dumper(\@args);
		my $i=$args[0];
		if (looks_like_number($i)) {
			return Dumper(\$BlitzerPOIS[$i]);
		} else {
			return Dumper(\@BlitzerPOIS);
		}
		return;
	}
	elsif($opt eq "hash")
	{
	   Log3 $name, 5, "hash = ".Dumper(\$hash);
	   return Dumper(\$hash);
	}
	elsif($opt eq "MapHTML")
	{
	   return "<plaintext>".Blitzer_CreateMap($hash);
	}
	
	else
	{
		return "Unknown argument $opt, choose one of allReadings hash MapHTML";
	}
}

#####################################
sub Blitzer_summaryFn($$$$){
	my ($FW_wname, $d, $room, $pageHash) = @_;										# pageHash is set fosummaryFn.
	my $hash   = $defs{$d};
	my $name = $hash->{NAME};
	my $stateFormat = AttrVal($name, "stateFormat", undef);
  
	if (defined($stateFormat)){
		return ;
	}
  
	my $html;
	$html = "<div><table class=\"block wide\"><tr>"; 
  
	my $img = FW_makeImage("refresh");
	my $cmd = "cmd.$name=set $name Update";
	$html.="<td><a onClick=\"FW_cmd('$FW_ME$FW_subdir?XHR=1&$cmd')\">$img</a></td>";
	$html.="<td>".ReadingsVal($name, "html", "")."</td>";
	$html .= "</tr></table></div>"; 
	if (AttrVal($name,"MapShow",0) == 1){
		$html .= Blitzer_CreateMap($hash);
	}
	return $html;
}

#####################################
sub Blitzer_SetTimer($) {
	my $hash = shift;
	my $name = $hash->{NAME};
	my $disabled = AttrVal($name, "disable", 0);
	
	my $refreshIntervall = $hash->{refreshIntervall}; #AttrVal($name, "refreshIntervall", 0);
	#Timer neu setzen
	if (($refreshIntervall == 0)||($disabled == 1)){
		RemoveInternalTimer($hash);
		readingsDelete($hash,"NextUpdate") if defined ReadingsVal($name,"NextUpdate",undef);
	} else {
		my $nextIntervall=gettimeofday() + ($refreshIntervall * 60);
		RemoveInternalTimer($hash);
		InternalTimer($nextIntervall, "Blitzer_Update", $hash);
		readingsSingleUpdate($hash, "NextUpdate", localtime($nextIntervall), 1);
	}
}

#####################################
sub Blitzer_DelTimer($) {
	my $hash = shift;
	my $name = $hash->{NAME};
	
	RemoveInternalTimer($hash);
	readingsDelete($hash,"NextUpdate") if defined ReadingsVal($name,"NextUpdate",undef);
}

#####################################
sub Blitzer_SetArea($) {
	my $hash = shift;
	my $name = $hash->{NAME};
	
	my $lat = AttrVal($name, "home_latitude", undef);
	my $lng = AttrVal($name, "home_longitude", undef);
	my $radius = AttrVal($name, "radius", undef);
	
	if (not defined($lat)){
		readingsSingleUpdate($hash, "Error", "Error: set home_latitude first!", 1);
		return;
	}
	if (not defined($lng)){
		readingsSingleUpdate($hash, "Error", "Error: set home_longitude first!", 1);
		return;
	}
	if (not defined($radius)){
		readingsSingleUpdate($hash, "Error", "Error: set radius first!", 1);
		return;
	}
	
	my @Coords = Blitzer_GetCoordinates($hash, $lat, $lng, $radius, 45);
	$attr{$name}{area_topRight_latitude} =  $Coords[0];
	$attr{$name}{area_topRight_longitude} =  $Coords[1];
	@Coords = Blitzer_GetCoordinates($hash, $lat, $lng, $radius, 225);
	$attr{$name}{area_bottomLeft_latitude} = $Coords[0];
	$attr{$name}{area_bottomLeft_longitude} =  $Coords[1];
	
}

#####################################
sub Blitzer_Update($$$$){
	my $hash = shift;
	my $cmd2 = shift;
	my $cmd3 = shift;
	my $cmd4 = shift;
	my $name = $hash->{NAME};
	
	my $updateReading = AttrVal($name, "createUpdateReading", 0);
	if ($updateReading == 1){
		readingsSingleUpdate($hash, "status", "refreshing", 1);
	}
		
	#Timer neu setzen
	Blitzer_SetTimer($hash);
	
	readingsDelete($hash, "Error");
		
	delete $hash->{tempCoord_Lat};
	delete $hash->{tempCoord_Long};
		    
	my $area_bottomLeft_latitude = $attr{$name}{area_bottomLeft_latitude}; 
	my $area_bottomLeft_longitude = $attr{$name}{area_bottomLeft_longitude};
	my $area_topRight_latitude = $attr{$name}{area_topRight_latitude};
	my $area_topRight_longitude = $attr{$name}{area_topRight_longitude};
	
	$hash->{tempRadius} = undef;
	#Neue Area berechnen, wenn Koordinaten mitgeliefert
	if (defined($cmd3)){
		Log3 $name, 4, "NEUE KOORDINATEN: $cmd2 $cmd3";
		Log3 $name, 4, "NEUER RADIUS: $cmd4" if(defined ($cmd4));;
		$hash->{tempCoord_Lat}=$cmd2;
		$hash->{tempCoord_Long}=$cmd3;
		my $newRadius = AttrVal($name, "radius", 10);
		if (defined ($cmd4)){
			$newRadius = $cmd4;
			$hash->{tempRadius}=$newRadius;
		}
		my @Coords = Blitzer_GetCoordinates($hash, $cmd2, $cmd3, $newRadius, 45);
		$area_topRight_latitude = $Coords[0];
		$area_topRight_longitude = $Coords[1];
		@Coords = Blitzer_GetCoordinates($hash, $cmd2, $cmd3, $newRadius, 225);
		$area_bottomLeft_latitude = $Coords[0];
		$area_bottomLeft_longitude = $Coords[1];
		Log3 $name, 4, "NEUE KOORDINATEN: $area_bottomLeft_latitude  $area_bottomLeft_longitude  $area_topRight_latitude  $area_topRight_longitude ";
	} else {
		##Die Werte sind unbedingt erforderlich!
		if (not defined($area_bottomLeft_latitude)){
			readingsSingleUpdate($hash, "Error", "Error: set area_bottomLeft_latitude first!", 1);
			return;
		}
		if (not defined($area_bottomLeft_longitude)){
			readingsSingleUpdate($hash, "Error", "Error: set area_bottomLeft_longitude first!", 1);
			return;
		}
		if (not defined($area_topRight_latitude)){
			readingsSingleUpdate($hash, "Error", "Error: set area_topRight_latitude first!", 1);
			return;
		}
		if (not defined($area_topRight_longitude)){
			readingsSingleUpdate($hash, "Error", "Error: set area_topRight_longitude first!", 1);
			return;
		}
	}

	
	my $HTTPTimeout = AttrVal($name, "httpGetTimeout", 5);
	#Zunächst die Blitzerdaten
	#https://cdn2.atudo.net/api/1.0/vl.php?type=0,1,2,3,4,5,6&box=52.xxxxxx,8.xxxxxx,53.xxxxxx,9.xxxxxx
	my $ShowFixed = AttrVal($name, "ShowFixed", 0);
	my $GetType = "0,1,2,3,4,5,6";
	if ($ShowFixed == 1){
		$GetType = "0,1,2,3,4,5,6,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115";
	} 
	#0,1,2,3,4,5,6,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115
	my $param = {
		url        => "https://cdn2.atudo.net/api/1.0/vl.php?type=$GetType&box=$area_bottomLeft_latitude,$area_bottomLeft_longitude,$area_topRight_latitude,$area_topRight_longitude",
		timeout    => $HTTPTimeout,
		method     => "GET",            # Lesen von Inhalten
		hash       => $hash,            # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
		header     => "",
		callback   =>  \&Blitzer_BlitzerDatenCallback   # Diese Funktion soll das Ergebnis dieser HTTP Anfrage bearbeiten
	};	#agent: FHEM/1.0\r\nUser-Agent: FHEM/1.0\r\nAccept: application/json
	Log3 $name, 5, "Blitzer: get param = ".Dumper(\$param);
	HttpUtils_NonblockingGet($param);      # Starten der HTTP Abfrage. Es gibt keinen Return-Code.
	
	return;

}

###################################
sub Blitzer_BlitzerDatenCallback($) {
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};
	
	my $DontUseOSM = AttrVal($name, "DontUseOSM", 0);
	
	if($err ne "")      # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
    {
        Log3 $name, 3, "error while requesting ".$param->{url}." - $err";   # Eintrag fürs Log
		readingsBeginUpdate($hash);
		my $updateReading = AttrVal($name, "createUpdateReading", 0);
		if ($updateReading == 1){
			readingsBulkUpdate($hash, "status", "Error ".$err, 1);
		}
		readingsBulkUpdate($hash, "Error", "error while requesting ".$param->{url}." - $err", 1);
		readingsEndUpdate($hash, 1);
		return;
    }
	
	Log3 $name, 5, "Blitzer: param = ".Dumper(\$param);
	Log3 $name, 4, "Blitzer: err = $err";
	Log3 $name, 4, "Blitzer: data = $data";
	
	my $decoded_json = decode_json( $data );
	Log3 $name, 5, "Blitzer: param = ".Dumper(\$decoded_json);
	my $pois = $decoded_json->{'pois'};
	Log3 $name, 5, "Blitzer: pois = ".Dumper(\$pois);
	
	my @poisArray = @{$pois};
	Log3 $name, 5, "Blitzer: Poi Anzahl = ".scalar(@poisArray);
	
	#'backend' => '0-11093088',
    #'confirm_date' => '0000-00-00 00:00:00',
    #'content' => '4721925411',
    #'counter' => '0',
    #'create_date' => '2019-02-09 11:04:03',
    #'gps_status' => '-',
    #'id' => '3228646049',
    #'info' => '{"count_180d":"2"}',
    #'lat' => '52.432697',
    #'lat_s' => '52.4',
    #'lng' => '13.237729',
    #'lng_s' => '13.2',
    #'polyline' => '',
    #'street' => 'Potsdamer Chaussee',
    #'type' => '1',
    #'vmax' => '50'
		
	#Liste mit den blitzern erstellen, dabei die Entfernung bereits berücksichtigen!
	my @FilteredpoisArray;
	Log3 $name, 4, "Blitzer: name = ".$name;
	my $radius = AttrVal($name, "radius", 9999);
	#TemporärenRadius mit einbeziehen!
	my $tempRadius = $hash->{tempRadius};
	if (defined($tempRadius)){
		$radius = $tempRadius;
	}
	
	my $lat = AttrVal($name, "home_latitude", 52);
	my $lng = AttrVal($name, "home_longitude", 8);
	
	#Wenn temoräre Werte verfügbar -> diese benutzen!
	my $tempLat = $hash->{tempCoord_Lat};	
	my $tempLong = $hash->{tempCoord_Long};	
	if (defined($tempLat)){
		$lat = $tempLat;
		$lng = $tempLong;
	}
	
	foreach my $item(@poisArray){
		my $Poi_lat = $item->{lat};
		my $Poi_lng = $item->{lng};
		Log3 $name, 4, "Blitzer: lat/lng = $Poi_lat $Poi_lng";
		my $Poi_street = $item->{street};
		my $Poi_vmax = $item->{vmax};
		
		my $id = $item->{id};
		        
        #Entfernung zur Home-Koordinate (Luftlinie)
        #Berechnung nach: https://www.kompf.de/gps/distcalc.html
        #Einfache Variante
        my $dx = 71.5 * abs($lng - $Poi_lng);
        my $dy = 111.3 * abs($lat - $Poi_lat);
		my $distance = sqrt($dx * $dx + $dy * $dy);
        
		#MaxEntfernung einbeziehen
		if (not $distance > $radius){
			Log3 $name, 4, "Blitzer: Distance = $distance < $radius";
			$item->{distance} = $distance;
			$item->{distanceShort} = sprintf("%.1f",$distance);
        	#push @Liste, [ $distance, $id, $Poi_street, $Poi_vmax, $Poi_lat, $Poi_lng ];	
			push @FilteredpoisArray, $item;
		} else {
			Log3 $name, 4, "Blitzer: Distance > Radius = $distance > $radius";
		}
		
		#Google Maps Link
		#https://www.google.com/maps/search/?api=1&query=36.26577,-92.54324
		$item->{MapLink} = "<a target=\"_blank\" rel=\"noopener noreferrer\" href=\"https://www.google.com/maps/search/?api=1&query=$Poi_lat,$Poi_lng\">Map</a>";
	}
	
	my @sorted =  sort { $a->{distance} <=> $b->{distance} } @FilteredpoisArray;
	my $size = @sorted;
	my $MaxAnzahlBlitzer = AttrVal($name, "MaxSpeedCameras", 0);
	if ($MaxAnzahlBlitzer != 0){
		#Löschen nicht benötigter Elemente
		splice(@sorted, $MaxAnzahlBlitzer);
	}
	
	Log3 $name, 4, "Blitzer: sorted = ".Dumper(\@sorted);
	#Liste merken
	@BlitzerPOIS = @sorted;
	
	if ($size == 0){
		#keine Blitzer!
		Blitzer_CreateHTML($hash);
	} else {
		#Wenn OSM nicht benutzt werden soll
		if ($DontUseOSM == 1){
			Blitzer_CreateHTML($hash);
		} else {
			#Orte über Openstreetmap einlesen
			foreach my $item(@sorted){
				my $Poi_lat = $item->{lat};
				my $Poi_lng = $item->{lng};
		
				my $mydata;
				$mydata->{hash}=$hash;
				$mydata->{item}=$item;
				
				my $HTTPTimeout = AttrVal($name, "httpGetTimeout", 5);
				my $param = {
					url        => "https://nominatim.openstreetmap.org/reverse?format=json&lat=".$Poi_lat."&lon=".$Poi_lng,
					timeout    => $HTTPTimeout,
					method     => "GET",            # Lesen von Inhalten
					hash       => $mydata,            # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
					header     => "",
					callback   =>  \&Blitzer_getOrteCallback   # Diese Funktion soll das Ergebnis dieser HTTP Anfrage bearbeiten
				};
				#agent: FHEM/1.0\r\nUser-Agent: FHEM/1.0\r\nAccept: application/json
				Log3 $name, 5, "Blitzer: get param = ".Dumper(\$param);
	
				HttpUtils_NonblockingGet($param);      # Starten der HTTP Abfrage. Es gibt keinen Return-Code.
				}
		}
		
	}
	return;
}

sub Blitzer_CreateMap($){
	my $hash = shift;
	my $name = $hash->{NAME};
	my $HomeLat = AttrVal("$name", "home_latitude", "52.000");
	my $HomeLng = AttrVal("$name", "home_longitude", "8.000");
	my $Width = AttrVal("$name", "MapWidth", "600px"); 
	my $Height = AttrVal("$name", "MapHeight", "400px"); 
	my $html.=<<'EOF';
<!DOCTYPE html>
<html lang="de">
   <head>
      <meta charset="UTF-8">
      <!-- <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" /> -->
      <title>HowTo: Mini-Beispiel "Leaflet Karte mit Marker"</title>
      <!-- leaflet.css und leaflet.js von externer Quelle einbinden -->
      <link rel="stylesheet" href="https://unpkg.com/leaflet@1.5.1/dist/leaflet.css" />
      <script src="https://unpkg.com/leaflet@1.5.1/dist/leaflet.js"></script>
   </head>
   <body>
EOF
	$html .= "<div id='meineKarte' style='height: $Height; width: $Width;'></div>";
	$html .=<<'EOF';
      <!-- OSM-Basiskarte einfügen und zentrieren -->
      <script type='text/javascript'>
	  var greenIcon = new L.Icon({
		iconUrl: 'https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-green.png',
		shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
		iconSize: [25, 41],
		iconAnchor: [12, 41],
		popupAnchor: [1, -34],
		shadowSize: [41, 41]
});
	var redIcon = new L.Icon({
		iconUrl: 'https://cdn.rawgit.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-red.png',
		shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
		iconSize: [25, 41],
		iconAnchor: [12, 41],
		popupAnchor: [1, -34],
		shadowSize: [41, 41]
});
EOF
         $html .= "var Karte = L.map('meineKarte').setView([$HomeLat, $HomeLng], 12);";
         $html .=<<'EOF';
		 L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
         'attribution':  'Kartendaten &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> Mitwirkende',
         'useCache': true
         }).addTo(Karte);
      </script>
      <!-- Marker einfügen -->
      <script>
EOF
	#Home Marker
	$html .= "var marker0 = L.marker([".$HomeLat.",".$HomeLng."], {icon: greenIcon}).addTo(Karte).bindPopup(\"Home\"); ";
	
	#Marker erstellen
	my $MarkerI=0;
	my $Markers="";
	for my $POI(@BlitzerPOIS){
		$MarkerI += 1;
		my $Text = ($POI->{vmax})." Km/h<br>";
		$Text .= ($POI->{display_name})."<br>";
		$Text .= "Erstellt: ".($POI->{create_date})."<br>";
		$Text .= "Zuletzt gesehen: ".($POI->{confirm_date});
		
		my $POIType = $POI->{type};
		my @values = ("101","102","103","104","105","106","107","108","109","110","111","112","113","114","115");
		if ( grep( /^$POIType$/, @values ) ) {
			$Text = "Festinstallierter Blitzer<br>".$Text;
			$html .= "var marker".$MarkerI." = L.marker([".($POI->{lat}).",".($POI->{lng})."], {icon: redIcon}).addTo(Karte).bindPopup(\"$Text\"); ";
		} else {
			$html .= "var marker".$MarkerI." = L.marker([".($POI->{lat}).",".($POI->{lng})."]).addTo(Karte).bindPopup(\"$Text\"); ";
		}
		
		
		if ($MarkerI == 1){
			$Markers .= "marker".$MarkerI;
		} else {
			$Markers .= ",marker".$MarkerI;
		}
	}
	if ($MarkerI > 0){
		
		$html .= "var group = new L.featureGroup([marker0,".$Markers."]); ";
		$html .= "Karte.fitBounds(group.getBounds());";
	}
	$html .=<<'EOF';
      </script>
   </body>
</html>
EOF
	
	return $html;

}

###################################
sub Blitzer_getOrteCallback($){
	my ($param, $err, $data) = @_;
	my $mydata = $param->{hash};
	my $hash = $mydata->{hash};
	my $tempitem = $mydata->{item};
	my $name = $hash->{NAME};
	
	Log3 $name, 5, "Blitzer: tempitem = ".Dumper(\$tempitem);
	
	# wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
	if($err ne ""){      
		Log3 "[getBlitzerOrte]", 3, "error while requesting ".$param->{url}." - $err";   # Eintrag fürs Log
		readingsBeginUpdate($hash);
		my $updateReading = AttrVal($name, "createUpdateReading", 0);
		if ($updateReading == 1){
			readingsBulkUpdate($hash, "status", "Error ".$err, 1);
		}
		readingsBulkUpdate($hash, "Error", "error while requesting ".$param->{url}." - $err", 1);
		readingsEndUpdate($hash, 1); 		# Notify is done by Dispatch
		return;
	}
	
	Log3 $name, 5, "Blitzer: param = ".Dumper(\$param);
	Log3 $name, 4, "Blitzer: err = $err";
	Log3 $name, 4, "Blitzer: data = $data";
	
	#item aus @BlitzerPOIS
	#Hinzufügen der Werte
	#"place_id":"41142197","licence":"Data © OpenStreetMap contributors, ODbL 1.0. https://osm.org/copyright","osm_type":"node","osm_id":"3034738834","lat":"52.5461408","lon":"13.3711899",
	#"display_name":"85, Pankstraße, Gesundbrunnen, Mitte, Berlin, 13357, Deutschland",
	#"address":{"house_number":"85","road":"Pankstraße","suburb":"Gesundbrunnen","city_district":"Mitte","city":"Berlin",7
	#"postcode":"13357","country":"Deutschland","country_code":"de"},"boundingbox":["52.5460408","52.5462408","13.3710899","13.3712899"]
	my $Anzahl = scalar(@BlitzerPOIS);
	for (my $i=0;$i<$Anzahl;$i++){
		if ($BlitzerPOIS[$i]->{id} eq $tempitem->{id}){
			Log3 $name, 4, "Blitzer: i = $i";
			for my $value(@Werte){
				($BlitzerPOIS[$i]->{$value}) = $data =~ m/$value":"([^"]+)"/;
			}
			$BlitzerPOIS[$i]->{ready} = 1;
			#(@BlitzerPOIS[$i]->{display_name}) = $data =~ m/display_name":"([^"]+)"/;
			last;
		}
	}
	Log3 $name, 5, "Blitzer: BlitzerPOIS = ".Dumper(\@BlitzerPOIS);
	
	#Testen, ob alle eingelesen worden sind
	my $alle = 1;
	for my $POIItem2(@BlitzerPOIS){
		Log3 $name, 5, "Blitzer: POIItem2 = ".Dumper(\$POIItem2);
		if(not defined($POIItem2->{ready})){
			$alle=0;
			#$hash->{STATE} = "PENDING";
			last;
		}
	}
	if ($alle eq 1){
		#$hash->{STATE} = "READY";
		Log3 $name, 5, "Blitzer: alle = ".Dumper(\@BlitzerPOIS);
	} else {
		#Noch nicht alle eingelesen!
		return;
	}
	
	#Readings setzen
	
	#Zunächst die Readings löschen, wenn vorhanden!
	for (my $i=0;$i<999;$i++){
		my $num = sprintf("%02d", $i);
		last if !defined ReadingsVal($name,$num."id",undef);
		for my $value(@Werte){
			readingsDelete($hash, $num."$value");
		}
		for my $value(@WerteVL){
			readingsDelete($hash, $num."$value");
		}
	}
	
	#Alle readings erzeugen, wenn gewünscht
	#Sie sind sonst in der globalen Variable gespeichert!!
	if (AttrVal($name, "createAllReadings", 0) eq "1"){
		readingsBeginUpdate($hash);
		
		my $Anzahl = scalar(@BlitzerPOIS);
		for (my $i=0;$i<$Anzahl;$i++) {
			my $num = sprintf("%02d", $i);
			
			for my $value(@Werte){
				readingsBulkUpdate($hash, $num."$value", $BlitzerPOIS[$i]->{$value}, 1);
			}
			for my $value(@WerteVL){
				readingsBulkUpdate($hash, $num."$value", $BlitzerPOIS[$i]->{$value}, 1);
			}
		}
		readingsEndUpdate($hash, 1); 		# Notify is done by Dispatch
	}
	
	Blitzer_CreateHTML($hash);

	return;
	
}

###################################
sub Blitzer_CreateHTML($){
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my $createNoHTML = AttrVal($name, "createNoHTML", 0);
	
	if (not defined(AttrVal($name, "Ausgabe", undef))){
		readingsSingleUpdate($hash, "Error", "Error: Erst Attribut Ausgabe setzen!", 1);
		return;
	}
	my @Ausgabe=split /,/, AttrVal($name, "Ausgabe", undef);
	
	my $Anzahl = scalar(@BlitzerPOIS);
	my $html="";
	my $htmlVor = AttrVal($name, "HTML_Before", "<html> <p align='left'>");
	my $htmlNach = AttrVal($name, "HTML_After", "</p></html>");
	my $htmlWithout = AttrVal($name, "HTML_Without", "<html> <p align='left'>Keine Blitzer in der Nähe.</p></html>");
	my $TextWithout = AttrVal($name, "Text_Without", "Keine Blitzer in der Nähe.");
	
	if ($Anzahl == 0){
		if ($createNoHTML == 0){
			$html = $htmlWithout;
		} else {
			$html = $TextWithout;
		}
		
	} else {
		if ($createNoHTML == 0){
			$html = $htmlVor;
		}
		
		#Wenn zu viele:
		#"id": 1,
		#"lat": 50.635690341007,
		#"lng": 6.260009765625,
		#"type": 1000,
		#"info": "{\"count_cluster\":16}"
		my $countNotVisible = 0;
		foreach my $NVPOI(@BlitzerPOIS){
			if ($NVPOI->{type} == 1000){
				my $countNV = $NVPOI->{info};
				#Log3 $name, 3, "$countNV";
				$countNV =~ s/{\"count_cluster\"://g;
				#Log3 $name, 3, "$countNV";
				$countNV =~ s/}//g;
				#Log3 $name, 3, "$countNV";
				$countNotVisible += $countNV; 
				#Log3 $name, 3, "$countNotVisible";
			}
		}
		if ($countNotVisible > 0){
			if ($createNoHTML == 0){
				$html .= "Weitere ".$countNotVisible." Blitzer vorhanden. Bitte Bereich verkleinern!<br>";
			} else {
				$html .= "Weitere ".$countNotVisible." Blitzer vorhanden. Bitte Bereich verkleinern!\n";
			}
			
		}
				
		my $SollAnzeige=0;
		my $IsOR = 0;
		my $PrevHasValue = 0;
		for (my $i=0;$i<$Anzahl;$i++) {
			foreach my $item(@Ausgabe){
							
				if (substr($item, 0, 1) eq "["){
					$html.=substr($item, 1, -1)." ";
					next;
				}
				if ($item eq "number"){
					$html.=sprintf("%02d", $i)." ";
					next;
				}
				if ($item eq "newline"){
					if ($createNoHTML == 0){
						$html.="<br>";
					} else {
						$html.=" \n";
					}
					
					next;
				}
		
				#START OR
				if (substr($item, 0, 1) eq "{"){
					if (substr($item, 1, 2) eq "OR"){
						$IsOR = 1;
					}
				}
				#END OR
				if (substr($item, 0, 1) eq "}"){
					$IsOR = 0;
					$PrevHasValue = 0;
				}
      
				if (defined $BlitzerPOIS[$i]->{$item}){
					#Bei einer "OR"-VErknüpfung nichts eintragen, wenn der vorherige einen Wert hatte
					if ($PrevHasValue == 0){
						$html.=$BlitzerPOIS[$i]->{$item}." ";
					}
					if ($IsOR == 1){
						$PrevHasValue = 1;
					}
				}
			}
		}
		if ($createNoHTML == 0){
			$html.=$htmlNach;
		}
	}
	
	#Anzahl hinzufügen
	$html =~ s/<Anzahl>/$Anzahl/g;
	
	#Sonderzeichen ersetzen
	if ($createNoHTML == 0){
		$html = Blitzer_translateHTML($html);
	} else {
		$html = Blitzer_translateTEXT($html);
	}
	
	
	
	Log3 $name, 4, "Blitzer: html = $html";
	
	#Readings nur neu, wenn auch neue Werte!
	readingsBeginUpdate($hash);
	readingsBulkUpdateIfChanged($hash, "html", $html, 1);
	if ($Anzahl == 0){
		readingsBulkUpdateIfChanged($hash, "Anzeige", "0", 1);
	} else {
		readingsBulkUpdateIfChanged($hash, "Anzeige", "1", 1);
	}
	my $updateReading = AttrVal($name, "createUpdateReading", 0);
	if ($updateReading == 1){
		readingsBulkUpdate($hash, "status", "ok", 1);
		readingsBulkUpdate($hash, "lastUpdate", localtime(), 1);
	}
	my $CountSpeedCameras = AttrVal($name, "createCountReading", 0);
	if ($CountSpeedCameras == 1){
		readingsBulkUpdateIfChanged($hash, "count", $Anzahl, 1);
	}
	
	readingsEndUpdate($hash, 1); 		# Notify is done by Dispatch
	
}

###################################
sub Blitzer_GetCoordinates($$$$$){
  my ( $hash, $lat, $lng, $radius, $grad ) = @_;
  my $name = $hash->{NAME};
  
  Log3 $name, 4, "Koordinaten berechnen: $lat  $lng $radius km  $grad °";
  my $Abstand = sqrt($radius*$radius+$radius*$radius)*1000; #Angabe in Meter!
        
  #https://www.cachewiki.de/wiki/Wegpunktprojektion
  my $Dnord=(cos($grad*pi()/180)*$Abstand)/1850; #Ergebnis in Grad
  my $Dost=(sin($grad*pi()/180)*$Abstand)/(1850*cos(($lat)*pi()/180));
  my $new_lat=$lat+$Dnord/60;
  my $new_long=$lng+$Dost/60;
  Log3 $name, 4, "Koordinaten berechnen Abstand: $Abstand";
  Log3 $name, 4, "Koordinaten berechnen Dnord Dost: $Dnord $Dost";
  Log3 $name, 4, "Koordinaten berechnen lat/lng: $new_lat $new_long";
  my @Values=($new_lat,$new_long);
  return @Values;
}

sub Blitzer_translateHTML($) {
	my $text = shift;
	my %translate = ("ä" => "&auml;", 
				"Ä" => "&Auml;", 
				"ü" => "&uuml;", 
				"Ü" => "&Uuml;", 
				"ö" => "&ouml;", 
				"Ö" => "&Ouml;", 
				"ß" => "&szlig;", 
				"\x{df}" => "&szlig;", 
				"\x{c4}" => "&Auml;",
				"\x{e4}" => "&auml;",
				"\x{fc}" => "&uuml;", 
				"\x{dc}" => "&Uuml;", 
				"\x{f6}" => "&ouml;", 
				"\x{d6}" => "&Ouml;"
				);
	my $keys = join ("|", keys(%translate));
	$text =~ s/($keys)/$translate{$1}/g;
	return $text;
}

sub Blitzer_translateTEXT($) {
	my $text = shift;
	my %translate = (
				"&auml;" => "ä", 
				"&Auml;" => "Ä", 
				"&uuml;" => "ü", 
				"&Uuml;" => "Ü", 
				"&ouml;" => "ö", 
				"&Ouml;" => "Ö", 
				"&szlig;" => "ß", 
				"\x{df}" => "ß", 
				"\x{c4}" => "Ä",
				"\x{e4}" => "ä",
				"\x{fc}" => "ü", 
				"\x{dc}" => "Ü", 
				"\x{f6}" => "ö", 
				"\x{d6}" => "Ö"
				);
	my $keys = join ("|", keys(%translate));
	$text =~ s/($keys)/$translate{$1}/g;
	return $text;
}

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item [helper]
=item summary Show speed cameras in Germany
=item summary_DE Blitzer anzeigen
=begin html

<a name="Blitzer"></a>
<h3>Blitzer</h3>
<div>
	<ul>
			<p>The module Blitzer shows the current speed cameras in the environment in text form.<br>
				In addition, you can also view the speed cameras - within a defined radius around a point<br>
      </p>
			<h4>Example:</h4>
			<p><code>define myBlitzer Blitzer 30</code><br></p>
      
      <a name="Blitzer_Define"></a>
        <h4>Define</h4>
			<p><code>define &lt;NAME&gt; Blitzer 30</code><br>
        Definition of a speed camera module with a refresh interval of 30 minutes.<br>
      </p>
			<p><code>define &lt;NAME&gt; Blitzer 0</code><br>
        Definition of a speed camera module without automatic update.<br>
			</p>
			
		<h4>Tips:</h4>
		<p>Tips for the settings:<br>
		First create the device with the update interval. Then set the attributes for the home coordinates and the radius.<br>
		The area to be selected is then calculated automatically and entered in the corresponding readings. Can then be adjusted as needed.<br>
		</p>
		<p>For a quick test of this module select "_SetDemoValues". Then the speed cameras for Berlin are displayed.</p>
  </ul>
  
  <h4>Set</h4>
  <ul><a name="Blitzer_Set"></a>
    <li><a name="Update">Update</a><br>
      <code>set &lt;Blitzer-Device&gt; Update &lt;Optional:LAT&gt; &lt;Optional:LONG&gt; &lt;Optional:radius&gt;</code><br>
            Re-import the Blitzer. <br>
						If the optional LAT / LONG coordinates are specified, the map section for the center is recalculated with the specified radius<br>
						and only speed cameras in the radius of the specified coordinates are shown. <br>
						It is also possible to set a new temporary radius with new coordinates.
    </li>
	<li><a name="Voreinstellung_Ausgabe">Voreinstellung_Ausgabe &lt;Stadt/Land/.../...&gt; ((Preset_output <City / Country / ... / ...>)</a><br>
      <code>set &lt;Blitzer-Device&gt; Voreinstellung_Ausgabe &lt;Stadtgebiet/Landgebiet/.../...&gt;</code><br>
						Set the default for the output. Here the attribute "Output" is adjusted.<br>
						Further settings see attribute "Ausgabe" ("Output") 
    </li>
	<li><a name="_SetDemoValues">_SetDemoValues</a><br>
      <code>set &lt;Blitzer-Device&gt; _SetDemoValues</code><br>
						Set demo values ​​for the coordinates. (Berlin)<br>
						If values ​​already exist, they will NOT be overwritten!<br>
						If necessary, delete the existing readings first.<br>
    </li>
	<li><a name="_Berechne_area">_Berechne_area (Calculate_area)</a><br>
      <code>set &lt;Blitzer-Device&gt; _Berechne_area</code><br>
						Automatically calculate values ​​for the attributes area _... with the home coordinates and the radius.<br>
    </li>

	</ul>
	
  <h4>Get</h4>
  <ul><a name="Blitzer_Get"></a>
		<li><a name="allReadings">allReadings</a><br>
			<code>get &lt;Blitzer-Device&gt; allReadings &lt;Optional:Nummer&gt;</code><br>
            Returns all readings as a list. If a number is given, only the corresponding entries are shown.<br>
    </li>
    <li><a name="hash">hash</a><br>
			<code>get &lt;Blitzer-Device&gt; hash</code><br>
            Returns the complete %hash of the device (Debug)<br>
    </li>
	<li><a name="MapHTML">MapHTML</a><br>
			<code>get &lt;Blitzer-Device&gt; MapHTML</code><br>
            Returns the HTML-Code for the Map.<br>
    </li>
	</ul>
  
  <h4>Attributes</h4>
  <ul><a name="Blitzer_Attr"></a>
		<li><a name="Ausgabe">Ausgabe (output)</a><br>
			<code>attr &lt;Blitzer-Device&gt; Ausgabe &lt;Liste&gt;</code><br>
            List of values ​​displayed per speed camera.<br><br>
            <b>Special entries:</b><br>
            <table>
             <colgroup> <col width="120"></colgroup>
              <tr>
                <td>number</td>
                <td>numbering</td>
              </tr>
              <tr>
                <td>newline</td>
                <td>New line</td>
              </tr>
              <tr>
                <td>[Free text]</td>
                <td>Any text. This is taken over without the brackets.</td>
              </tr>
              <tr>
                <td>distance</td>
                <td>distance of the speed camera from the home coordinate (line of sight)</td>
              </tr>
              <tr>
                <td>distanceShort</td>
                <td>Distance of the speed camera from the home coordinate (line of sight), one decimal place</td>
              </tr>
			  <tr>
                <td>MapLink</td>
                <td>Link to Google Maps with the coordinate from the speed camera</td>
              </tr>
              <tr>
                <td>{OR</td>
                <td>OR operation. If there is a value, the subsequent ones (up to the curly bracket) are ignored</td>
              </tr>
              <tr>
                <td>}</td>
                <td>End of the OR operation. Must be mandatory if an OR operation is included.</td>
              </tr>
            </table>
            <br>You can also add as many own entries as you like.<br>
    </li>
    <li><a name="home_latitude">home_latitude</a><br>
			<code>attr &lt;Blitzer-Device&gt; home_latitude 52.00000</code><br>
            Geographical latitude of the home coordinate or midpoint.<br>
    </li>
    <li><a name="home_longitude">home_longitude</a><br>
			<code>attr &lt;Blitzer-Device&gt; home_longitude 7.00000</code><br>
            Geographical length of the home coordinate or midpoint.<br>
    </li>
    <li><a name="area_bottomLeft_latitude">area_bottomLeft_latitude</a><br>
			<code>attr &lt;Blitzer-Device&gt; area_bottomLeft_latitude 52.00000</code><br>
            The area in which the speed cameras are listed. (Bottom left)<br>
    </li>
    <li><a name="area_bottomLeft_longitude">area_bottomLeft_longitude</a><br>
			<code>attr &lt;Blitzer-Device&gt; area_bottomLeft_longitude 7.00000</code><br>
            The area in which the speed cameras are listed. (Bottom left)<br>
    </li>
    <li><a name="area_topRight_latitude">area_topRight_latitude</a><br>
			<code>attr &lt;Blitzer-Device&gt; area_topRight_latitude 52.00000</code><br>
            The area in which the speed cameras are listed. (Top right)<br>
    </li>
    <li><a name="area_topRight_longitude">area_topRight_longitude</a><br>
			<code>attr &lt;Blitzer-Device&gt; area_topRight_longitude 7.00000</code><br>
            The area in which the speed cameras are listed. (Top right)<br>
    </li>
    <li><a name="createAllReadings">createAllReadings</a><br>
			<code>attr &lt;Blitzer-Device&gt; createAllReadings 0|1</code><br>
            If all readings are needed this must be activated.<br>
    </li>
	<li><a name="createUpdateReading">createUpdateReading</a><br>
			<code>attr &lt;Blitzer-Device&gt; createUpdateReading 0|1</code><br>
            During the update, a reading (status) "refreshing" is displayed.<br>
			Once this is done, "ok" will be displayed, and a reading "lastUpdate" with the current date is displayed. <br>
			If an error occurs, "Error" is displayed.<br>
    </li>
    <li><a name="createNoHTML">createNoHTML</a><br>
			<code>attr &lt;Blitzer-Device&gt; createNoHTML 0|1</code><br>
            If the output is required in text form, this must be activated.<br>
    </li>
	<li><a name="DontUseOSM">DontUseOSM</a><br>
			<code>attr &lt;Blitzer-Device&gt; DontUseOSM 0|1</code><br>
            Do not use the location details from OSM (OpenStreetMap). There are then no longer all locations available!<br>
    </li>
    <li><a name="radius">radius</a><br>
			<code>attr &lt;Blitzer-Device&gt; radius &lt;Radius in km&gt;</code><br>
            Only speed cameras within xx km are displayed. (Set to 999 if not needed)<br>
    </li>
	<li><a name="MaxSpeedCameras">MaxSpeedCameras</a><br>
			<code>attr &lt;Blitzer-Device&gt; MaxSpeedCameras &lt;Anzahl anzuzeigender Blitzer&gt;</code><br>
            Only the next speed cameras in the corresponding number are displayed. Set to "0" to show all.<br>
    </li>
	<li><a name="createCountReading">createCountReading</a><br>
			<code>attr &lt;Blitzer-Device&gt; createCountReading 0|1</code><br>
            Create reading for number of speed Cameras.<br>
    </li>
    <li><a name="stateFormat">stateFormat</a><br>
			<code>attr &lt;Blitzer-Device&gt; stateFormat &lt;irgendwas&gt;</code><br>
            If no display is required in FHEM, the attribute can be used to override the display.<br>
    </li>
	<li><a name="httpGetTimeout">httpGetTimeout</a><br>
			<code>attr &lt;Blitzer-Device&gt; httpGetTimeout &lt;5&gt;</code><br>
            Wait (sec.) For an HTTP get command<br>
    </li>
	<li><a name="HTML_Before">HTML_Before</a><br>
			<code>attr &lt;Blitzer-Device&gt; HTML_Before &lt;HTML-Code&gt;</code><br>
            HTML before the text (without caption: &lt;html&gt; &lt;p align='left'&gt;)<br>
			If a text is to be e.g. "Current Speed ​​Cameras:" are displayed, here for example:<br>
			&lt;html&gt; &lt;p align='left'&gt;Current Speed ​​Cameras: &lt;br&gt; (default)<br>
			&lt;Anzahl&gt; will be replaced with the number of speed cameras.<br>
    </li>
	<li><a name="HTML_After">HTML_After</a><br>
			<code>attr &lt;Blitzer-Device&gt; HTML_After &lt;HTML-Code&gt;</code><br>
            HTML after the text (default: &lt;/p&gt;&lt;/html\&gt;)<br>
			&lt;Anzahl&gt; will be replaced with the number of speed cameras.<br>
    </li>
	<li><a name="HTML_Without">HTML_Without</a><br>
			<code>attr &lt;Blitzer-Device&gt; HTML_Without &lt;HTML-Code&gt;</code><br>
            HTML if there are no speed cameras (default: &lt;html&gt; &lt;p align='left'&gt;Keine Blitzer in der Nähe&lt;/p&gt;&lt;/html\&gt;)<br>
    </li>	
	<li><a name="Text_Without">Text_Without</a><br>
			<code>attr &lt;Blitzer-Device&gt; Text_Without &lt;Text&gt;</code><br>
            Text if there are no speed cameras (only if attr createNoHTML) (default: Keine Blitzer in der Nähe)<br>
    </li>
	<li><a name="disable">disable 0|1</a><br>
			<code>attr &lt;Blitzer-Device&gt; disable &lt;1|0&gt;</code><br>
            No automatic update<br>
    </li>	
	<li><a name="MapShow">MapShow 0|1</a><br>
			<code>attr &lt;Blitzer-Device&gt; MapShow &lt;1|0&gt;</code><br>
            Display a Map with the current speed Cameras.<br>
			<br>
			The Speed Cameras are shown as POI on the Map. The Map is automatically zoomed.<br>
			The	Home-coordinate is shown in green and the Speed Cameras are shown in Blue.<br>
			If you click on a POI in the map, further details of the speed camera are displayed.<br>
			<br>
			If there is no speed camera nearby, only the home coordinate will be displayed. <br>
			<br>
			Restriction: <br>
			There must be only one camera device in the room, otherwise there will be duplicate card definitions. <br>
    </li>	
	<li><a name="MapWidth">MapWidth</a><br>
			<code>attr &lt;Blitzer-Device&gt; MapWidth 600px</code><br>
            Only if MapShow 1<br>
			The width of the displayed map. Either the width in pixels (400px) <br>
			or the width in percent (100%) <br>
    </li>	
	<li><a name="MapHeight">MapHeight</a><br>
			<code>attr &lt;Blitzer-Dezvice&gt; MapHeight 600px</code><br>
			Only if MapShow 1<br>
			The height of the displayed map. Specify in pixels (400px) <br>
    </li>	
	<li><a name="ShowFixed">ShowFixed</a><br>
			<code>attr &lt;Blitzer-Dezvice&gt; ShowFixed &lt;1|0&gt;</code><br>
            Show also fixed Speed Cameras.<br>
    </li>	
	
	
    
  </ul>
  
  <h4>Readings</h4>
  <ul><a name="Blitzer_Readings"></a>
		<li><a name="html">html</a><br>
			The output of the speed camera as text or HTML<br>
    </li>
    <li><a name="Anzeige">Anzeige</a><br>
			If speed cameras are available: 1 <br>
			If there are no speed cameras: 0<br>
    </li>
	<li><a name="NextUpdate">NextUpdate</a><br>
			The next update<br>
    </li>
	<li><a name="lastUpdate">lastUpdate</a><br>
			Date / time of the last update<br>
    </li>
	<li><a name="status">status</a><br>
			"ok", if successfully read<br>
			"refreshing" when refreshing<br>
			"error" if the reading was faulty<br>
    </li>
	<li><a name="Error">Error</a><br>
			Error message, if available<br>
    </li>
  </ul>
    
</div>

=end html

=begin html_DE

<a name="Blitzer"></a>
<h3>Blitzer</h3>
<div>
	<ul>
			<p>Das Modul Blitzer zeigt die aktuellen Blitzer in der Umgebung in Textform an.<br>
         Zusätzlich kann man sich auch die Blitzer - in einem definierten Umkreis um einen Punkt - anzeigen lassen<br>
      </p>
			<h4>Beispiel:</h4>
			<p><code>define myBlitzer Blitzer 30</code><br></p>
      
      <a name="Blitzer_Define"></a>
        <h4>Define</h4>
			<p><code>define &lt;NAME&gt; Blitzer 30</code><br>
        Definition eines Blitzer Moduls mit einem Aktualisierungsintervall von 30 Minuten.<br>
      </p>
			<p><code>define &lt;NAME&gt; Blitzer 0</code><br>
        Definition eines Blitzer Moduls ohne automatische Aktualisierung.<br>
			</p>
			
		<h4>Tipps:</h4>
		<p>Tipps für die Einstellungen:<br>
		Zuerst das Device anlegen mit dem Aktualisierungsintervall. Danach die Attribute für die Home-Koordinaten und den Radius setzen.<br>
		Der Auszuwählende Bereich wird dann automatisch berechnet und in die entsprechenden Readings eingetragen. Kann bei Bdarf dann angepasst werden.<br>
		</p>
		<p>Für einen schnellen Test dieses Moduls "_SetDemoValues" auswählen. Dann werden die Blitzer für Berlin angezeigt.</p>
  </ul>
  
  <h4>Set</h4>
  <ul><a name="Blitzer_Set"></a>
    <li><a name="Update">Update</a><br>
      <code>set &lt;Blitzer-Device&gt; Update &lt;Optional:LAT&gt; &lt;Optional:LONG&gt;</code><br>
            Neu einlesen der Blitzer. <br>
						Werden die optionalen LAT/LONG Koordinaten mit angegeben, wird der Kartenausschnitt für den Mittelpunkt mit dem angegebenen Radius neu berechnet <br>
						und nur Blitzer in dem Radius der angegebenen Koordinaten ausgegeben. <br>
						Es kann auch optional ein neuer temporärer Radius mit angegeben werden.
    </li>
	<li><a name="Voreinstellung_Ausgabe">Voreinstellung_Ausgabe &lt;Stadt/Land/.../...&gt;</a><br>
      <code>set &lt;Blitzer-Device&gt; Voreinstellung_Ausgabe &lt;Stadtgebiet/Landgebiet/.../...&gt;</code><br>
						Voreinstellung für die Ausgabe setzen. Hier wird das Attribut "Ausgabe" angepasst.<br>
						Weitere Einstellungen siehe Attribut "Ausgabe" 
    </li>
	<li><a name="_SetDemoValues">_SetDemoValues</a><br>
      <code>set &lt;Blitzer-Device&gt; _SetDemoValues</code><br>
						Demo-Werte für die Koordinaten setzen. (Berlin)<br>
						Wenn bereits Werte vorhanden sind, werden diese NICHT überschrieben!<br>
						Bei Bedarf die vorhandenen Readings erst löschen.<br>
    </li>
	<li><a name="_Berechne_area">_Berechne_area</a><br>
      <code>set &lt;Blitzer-Device&gt; _Berechne_area</code><br>
						Werte für die Attribute area_... automatisch berechnen mit den Home-Koordinaten und dem Radius.<br>
    </li>

	</ul>
	
  <h4>Get</h4>
  <ul><a name="Blitzer_Get"></a>
		<li><a name="allReadings">allReadings</a><br>
			<code>get &lt;Blitzer-Device&gt; allReadings &lt;Optional:Nummer&gt;</code><br>
            Gibt alle Readings als Liste aus. Wird eine nummer mitgegeben, werden nur die entsprechenden Einträge ausgeggeben.<br>
    </li>
    <li><a name="hash">hash</a><br>
			<code>get &lt;Blitzer-Device&gt; hash</code><br>
            Gibt den kompletten %hash des Devices aus (Debug)<br>
    </li>
	<li><a name="MapHTML">MapHTML</a><br>
			<code>get &lt;Blitzer-Device&gt; MapHTML</code><br>
            Gibt den HTML-Code für die Map aus.<br>
    </li>
	</ul>
  
  <h4>Attributes</h4>
  <ul><a name="Blitzer_Attr"></a>
		<li><a name="Ausgabe">Ausgabe</a><br>
			<code>attr &lt;Blitzer-Device&gt; Ausgabe &lt;Liste&gt;</code><br>
            Auflistung der Werte, die pro Blitzer angezeigt werden.<br><br>
            <b>Spezielle Einträge:</b><br>
            <table>
             <colgroup> <col width="120"></colgroup>
              <tr>
                <td>number</td>
                <td>Nummerierung</td>
              </tr>
              <tr>
                <td>newline</td>
                <td>Neue Zeile</td>
              </tr>
              <tr>
                <td>[Freitext]</td>
                <td>Beliebiger Text. Dieser wird ohne die Klammern übernommen.</td>
              </tr>
              <tr>
                <td>distance</td>
                <td>Abstand des Blitzers von der Home-Koordinate (Luftlinie)</td>
              </tr>
              <tr>
                <td>distanceShort</td>
                <td>Abstand des Blitzers von der Home-Koordinate (Luftlinie) eine Kommastelle</td>
              </tr>
			  <tr>
                <td>MapLink</td>
                <td>Link auf Google Maps mit der Koordinate des Blitzers</td>
              </tr>
              <tr>
                <td>{OR</td>
                <td>ODER-Verknüpfung. Wenn ein Wert vorhanden ist, werden die nachfolgenden (bis zur geschweiften Klammer) nicht berücksichtigt</td>
              </tr>
              <tr>
                <td>}</td>
                <td>Ende der ODER-Verknüpfung. Muss zwingend gesetzt werden, wenn eine ODER-Verknüpfung enthalten ist.</td>
              </tr>
            </table>
            <br>Es können auch beliebig viele eigene Einträge hinzugefügt werden.<br>
    </li>
    <li><a name="home_latitude">home_latitude</a><br>
			<code>attr &lt;Blitzer-Device&gt; home_latitude 52.00000</code><br>
            Geographische Breite der Home-Koordinate bzw. des Mittelpunktes.<br>
    </li>
    <li><a name="home_longitude">home_longitude</a><br>
			<code>attr &lt;Blitzer-Device&gt; home_longitude 7.00000</code><br>
            Geographische Länge der Home-Koordinate bzw. des Mittelpunktes.<br>
    </li>
    <li><a name="area_bottomLeft_latitude">area_bottomLeft_latitude</a><br>
			<code>attr &lt;Blitzer-Device&gt; area_bottomLeft_latitude 52.00000</code><br>
            Der Bereich in dem die Blitzer aufgeführt werden. (Unten-Links)<br>
    </li>
    <li><a name="area_bottomLeft_longitude">area_bottomLeft_longitude</a><br>
			<code>attr &lt;Blitzer-Device&gt; area_bottomLeft_longitude 7.00000</code><br>
            Der Bereich in dem die Blitzer aufgeführt werden. (Unten-Links)<br>
    </li>
    <li><a name="area_topRight_latitude">area_topRight_latitude</a><br>
			<code>attr &lt;Blitzer-Device&gt; area_topRight_latitude 52.00000</code><br>
            Der Bereich in dem die Blitzer aufgeführt werden. (Oben-Rechts)<br>
    </li>
    <li><a name="area_topRight_longitude">area_topRight_longitude</a><br>
			<code>attr &lt;Blitzer-Device&gt; area_topRight_longitude 7.00000</code><br>
            Der Bereich in dem die Blitzer aufgeführt werden. (Oben-Rechts)<br>
    </li>
    <li><a name="createAllReadings">createAllReadings</a><br>
			<code>attr &lt;Blitzer-Device&gt; createAllReadings 0|1</code><br>
            Wenn alle Readings benötigt werden muss dies aktiviert werden.<br>
    </li>
	<li><a name="createUpdateReading">createUpdateReading</a><br>
			<code>attr &lt;Blitzer-Device&gt; createUpdateReading 0|1</code><br>
            Während des Updates wird ein Reading(status) "refreshing" angezeigt.<br>
			Sobald das einelsen abgeschlossen ist, wird "ok" angezeigt, und <br>
			es wird ein Reading "lastUpdate" mit dem aktuellem Datum angezeigt.<br>
			Bei einem Fehler wird "Error" angezeigt.<br>
    </li>
    <li><a name="createNoHTML">createNoHTML</a><br>
			<code>attr &lt;Blitzer-Device&gt; createNoHTML 0|1</code><br>
            Wenn die ausgabe in Textform benötigt wird muss dies aktiviert werden.<br>
    </li>
	<li><a name="DontUseOSM">DontUseOSM</a><br>
			<code>attr &lt;Blitzer-Device&gt; DontUseOSM 0|1</code><br>
            Die Ortsangaben nicht von OSM (OpenStreetMap) benutzen. Es stehen dann nicht mehr alle Ortsangaben zur Verfügung!<br>
    </li>
    <li><a name="radius">radius</a><br>
			<code>attr &lt;Blitzer-Device&gt; radius &lt;Radius in km&gt;</code><br>
            Es werden nur Blitzer im Umkreis von xx km angezeigt. (Auf 999 setzen, wenn es nicht benötigt wird)<br>
    </li>
	<li><a name="MaxSpeedCameras">MaxSpeedCameras</a><br>
			<code>attr &lt;Blitzer-Device&gt; MaxSpeedCameras &lt;Anzahl anzuzeigender Blitzer&gt;</code><br>
            Es werden nur die nächsten Blitzer in der entsprechenden Anzahl angezeigt. Auf "0" setzen um alle anzuzeigen.<br>
    </li>
	<li><a name="createCountReading">createCountReading</a><br>
			<code>attr &lt;Blitzer-Device&gt; createCountReading 0|1</code><br>
            Es wird ein reading erzeugt, das die Anzahl der gefundenen Blitzer anzeigt.<br>
    </li>
    <li><a name="stateFormat">stateFormat</a><br>
			<code>attr &lt;Blitzer-Device&gt; stateFormat &lt;irgendwas&gt;</code><br>
            Wird keine Anzeige in FHEM benötigt, kann über das Attribut die Anzeige übergangen werden.<br>
    </li>
	<li><a name="httpGetTimeout">httpGetTimeout</a><br>
			<code>attr &lt;Blitzer-Device&gt; httpGetTimeout &lt;5&gt;</code><br>
            Wartezeit (sek.) auf einen HTTP-Get Befehl<br>
    </li>
	<li><a name="HTML_Before">HTML_Before</a><br>
			<code>attr &lt;Blitzer-Device&gt; HTML_Before &lt;HTML-Code&gt;</code><br>
            HTML vor dem Text (Ohne Beschriftung: &lt;html&gt; &lt;p align='left'&gt;)<br>
			Soll ein Text z.B. "Aktuelle Blitzer:" angezeigt werden, hier z.B.: <br>
			&lt;html&gt; &lt;p align='left'&gt;Aktuelle Blitzer:&lt;br&gt; (Standardeinstellung)<br>
			&lt;Anzahl&gt; wird mit der Anzahl der Blitzer ersetzt.<br>
    </li>
	<li><a name="HTML_After">HTML_After</a><br>
			<code>attr &lt;Blitzer-Device&gt; HTML_After &lt;HTML-Code&gt;</code><br>
            HTML nach dem Text (Standard: &lt;/p&gt;&lt;/html\&gt;)<br>
			&lt;Anzahl&gt; wird mit der Anzahl der Blitzer ersetzt.<br>
    </li>
	<li><a name="HTML_Without">HTML_Without</a><br>
			<code>attr &lt;Blitzer-Device&gt; HTML_Without &lt;HTML-Code&gt;</code><br>
            HTML, wenn keine Blitzer vorhanden sind (Standard: &lt;html&gt; &lt;p align='left'&gt;Keine Blitzer in der Nähe&lt;/p&gt;&lt;/html\&gt;)<br>
    </li>	
	<li><a name="Text_Without">Text_Without</a><br>
			<code>attr &lt;Blitzer-Device&gt; Text_Without &lt;Text&gt;</code><br>
            Text, wenn keine Blitzer vorhanden sind (Nur wenn attr createNoHTML) (Standard: Keine Blitzer in der Nähe)<br>
    </li>
	<li><a name="disable">disable 0|1</a><br>
			<code>attr &lt;Blitzer-Device&gt; disable &lt;1|0&gt;</code><br>
            Kein automatisches aktualisieren<br>
    </li>	
	<li><a name="MapShow">MapShow 0|1</a><br>
			<code>attr &lt;Blitzer-Device&gt; MapShow &lt;1|0&gt;</code><br>
            Karte mit den Blitzern anzeigen.<br>
			Es handelt sich um eine Dynamische Karte. Zommen und verschieben ist möglich.<br>
			<br>
			Die Blitzer werden als POI auf einer Karte angezeigt und der Kartenausschnitt automatisch<br>
			gezoomt. Die Home-Koordinate wird in Grün und alle Blitzerstandorte in Blau dargestellt.<br>
			Wir auf ein POI in der Karte geklickt, werden weitere Details zum Blitzer angezeigt.<br>
			<br>
			Ist kein Blitzer in der Nähe, wird nur die Home-Koordinate angezeigt.<br>
			<br>
			Einschränkung:<br>
			Es darf nur ein Blitzer-Device im Raum vorhanden sein, da es sonst zu doppelten Definitionen der Karte kommt.<br>
    </li>	
	<li><a name="MapWidth">MapWidth</a><br>
			<code>attr &lt;Blitzer-Device&gt; MapWidth 600px</code><br>
            Nur wenn MapShow 1 ist.<br>
			Die breite der angezeigten Karte. Entweder die Breite in Pixeln (400px)<br>
			oder die Breite in Prozent (100%)<br>
    </li>	
	<li><a name="MapHeight">MapHeight</a><br>
			<code>attr &lt;Blitzer-Dezvice&gt; MapHeight 600px</code><br>
            Nur wenn MapShow 1 ist.<br>
			Die Höhe der angezeigten Karte. In Pixeln angeben (400px)<br>
    </li>
	<li><a name="ShowFixed">ShowFixed</a><br>
			<code>attr &lt;Blitzer-Dezvice&gt; ShowFixed &lt;1|0&gt;</code><br>
            Auch die festinstallierten Blitzer anzeigen.<br>
    </li>	
	    
  </ul>
  
  <h4>Readings</h4>
  <ul><a name="Blitzer_Readings"></a>
		<li><a name="html">html</a><br>
			Die Ausgabe der Blitzer als Text oder HTML<br>
    </li>
    <li><a name="Anzeige">Anzeige</a><br>
			Wenn Blitzer vorhanden sind: 1 <br>
      Sind keine Blitzer vorhanden: 0<br>
    </li>
	<li><a name="NextUpdate">NextUpdate</a><br>
			Das nächste Update<br>
    </li>
	<li><a name="lastUpdate">lastUpdate</a><br>
			Datum/Uhrzeit der letzten Aktualisierung<br>
    </li>
	<li><a name="status">status</a><br>
			"ok", wenn erfolgreich eingelesen wurde<br>
			"refreshing", wenn gerade aktualisiert wird<br>
			"error", wenn das Einlesen fehlerhaft war
    </li>
	<li><a name="Error">Error</a><br>
			Fehlermeldung, wenn vorhanden<br>
    </li>
  </ul>
    
</div>

=end html_DE

=cut
