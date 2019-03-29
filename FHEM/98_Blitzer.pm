#######################################################################################################################################################
# $Id: 98_Blitzer.pm 29.03.2019 21:40
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
#- 
#Ideen:  
#- 2. Reading ermöglichen? 1x HTML + 1x Text ?
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
my @WerteVL=("backend","confirm_date","content","counter","create_date","distance","distanceShort","gps_status","id","info","lat","lat_s","lng","lng_s","polyline","street","type","vmax");

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
	
	
	$hash->{STATE} = "Defined";
	#$modules{Blitzer}{defptr}{$hash->{DEF}} = $hash;
	
	# Standards setzen 
	$attr{$name}{radius} = "10" if( not defined( $attr{$name}{radius} ) );
	$attr{$name}{Ausgabe} = $VoreinstellungenStandards{Stadt} if( not defined( $attr{$name}{Ausgabe} ) );
	$attr{$name}{createAllReadings} = "0" if( not defined( $attr{$name}{createAllReadings} ) );
	$attr{$name}{icon} = "message_attention" if( not defined( $attr{$name}{icon} ) );
	$attr{$name}{createNoHTML} = "0" if( not defined( $attr{$name}{createNoHTML} ) );
	$attr{$name}{createUpdateReading} = "1" if( not defined( $attr{$name}{createUpdateReading} ) );
	$attr{$name}{room} = "Blitzer" if( not defined( $attr{$name}{room} ) );
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
			if ($disabled == 1){
				Blitzer_DelTimer($hash);
			} else {
				#hash setzen!
				$attr{$name}{disable} = 0;
				Blitzer_Update($hash, undef, undef);
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
	
	if ($cmd eq "Voreinstellung_Ausgabe"){
		$attr{$name}{Ausgabe}=$VoreinstellungenStandards{$cmd2};
		return;
	}
	
	if ($cmd eq "Update"){
		Blitzer_Update($hash,$cmd2,$cmd3);
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
	
	else
	{
		return "Unknown argument $opt, choose one of allReadings hash";
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
sub Blitzer_Update($$$){
	my $hash = shift;
	my $cmd2 = shift;
	my $cmd3 = shift;
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
	
	#Neue Area berechnen, wenn Koordinaten mitgeliefert
	if (defined($cmd3)){
		Log3 $name, 4, "NEUE KOORDINATEN: $cmd2 $cmd3";
		$hash->{tempCoord_Lat}=$cmd2;
		$hash->{tempCoord_Long}=$cmd3;
		
		my @Coords = Blitzer_GetCoordinates($hash, $cmd2, $cmd3, AttrVal($name, "radius", 10), 45);
		$area_topRight_latitude = $Coords[0];
		$area_topRight_longitude = $Coords[1];
		@Coords = Blitzer_GetCoordinates($hash, $cmd2, $cmd3, AttrVal($name, "radius", 10), 225);
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
	my $param = {
		url        => "https://cdn2.atudo.net/api/1.0/vl.php?type=0,1,2,3,4,5,6&box=$area_bottomLeft_latitude,$area_bottomLeft_longitude,$area_topRight_latitude,$area_topRight_longitude",
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
			$hash->{STATE} = "PENDING";
			last;
		}
	}
	if ($alle eq 1){
		$hash->{STATE} = "READY";
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
<ul>No english documentation here yet, sorry.<br>

	<b>Define</b><br>
	<ul>
    <code>define &lt;NAME&gt; Blitzer &lt;Interval&gt;</code><br><br>
    <u>examples:</u>
		<ul>
      define &lt;NAME&gt; Interval 30<br>
    </ul>	
  </ul><br><br>

	<b>Set</b><br>
	<ul>N/A</ul><br><br>

	<b>Get</b><br>
	<ul>N/A</ul><br><br>

	<b>Attribute</b><br>
	<ul>N/A</ul>
	<br>
	
</ul>
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
						und nur Blitzer in dem Radius der angegebenen Koordinaten ausgegeben. 
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
    </li>
	<li><a name="HTML_After">HTML_After</a><br>
			<code>attr &lt;Blitzer-Device&gt; HTML_After &lt;HTML-Code&gt;</code><br>
            HTML nach dem Text (Standard: &lt;/p&gt;&lt;/html\&gt;)<br>
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
