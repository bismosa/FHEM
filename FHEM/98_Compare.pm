#######################################################################################################################################################
# $Id: 98_Compare.pm 01.2020
# 
# Dieses Modul vergleicht Attribute und Readings von gewählten Geräten
#
#  This code is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#######################################################################################################################################################

package main;

use strict;
use warnings;
use Date::Parse;

#####################################
sub Compare_Initialize($)
{
my ($hash) = @_;
    $hash->{DefFn}		= "Compare_Define";
    $hash->{UndefFn}	= "Compare_Undef";
    $hash->{AttrFn}		= "Compare_Attr";  
    $hash->{SetFn}		= "Compare_Set";
    #$hash->{GetFn}		= "Compare_Get";	
    #$hash->{ParseFn}	= "Compare_Parse";
    $hash->{AttrList}	= "ShowHASH:0,1 Values TableFormat:Devices,Readings,both ".$readingFnAttributes;
    
    $hash->{NotifyFn}	= "Compare_Notify";
    #$hash->{FW_summaryFn}	= "Compare_summaryFn";    # displays html instead of status icon in fhemweb room-view
    
    #$hash->{FW_hideDisplayName} = 1;               # Forum 88667 
    $hash->{FW_detailFn}	= "Compare_summaryFn";    # displays html instead of status icon in fhemweb room-view
    #$data{webCmdFn}{Compare} = "Compare_webCmdFn";	# displays rc instead of device-commands on the calling device
    #$hash->{FW_atPageEnd} = 1; 					          # wenn 1 -> kein Longpoll ohne informid in HTML-Tag
}

###################################
sub Compare_Define($$){

	my ($hash, $def) = @_;
	my $name = $hash->{NAME};
	my @a = split("[ \t][ \t]*", $def);
	
	Log3 $name, 4, "$name: Anzahl Argumente = ".int(@a);
	Log3 $name, 4, "$name: Argument0 = ".$a[0] if(int(@a) > 0);
	Log3 $name, 4, "$name: Argument1 = ".$a[1] if(int(@a) > 1);
	Log3 $name, 4, "$name: Argument2 = ".$a[2] if(int(@a) > 2);
	Log3 $name, 4, "$name: Argument3 = ".$a[3] if(int(@a) > 3);
	
	if ($init_done == 1){
		#nur beim ersten define setzen:
		#TODO!!! Welche Standards?
		$attr{$name}{ShowHASH} = 1 if( not defined( $attr{$name}{ShowHASH} ) );
    $attr{$name}{TableFormat} = "both" if( not defined( $attr{$name}{TableFormat} ) );
	} else {
		#Log3 $name, 1, "$name: already defined";
	}
	
	$hash->{STATE} = "Defined";
  	
	my $ok;
	if (defined($a[2])){
		$ok=1;
	}
	return "Wrong syntax: use define <name> Compare <Devices-Regex>" if (!$ok);
	
	return undef;
}

#####################################
sub Compare_Undef($$) {
	my ($hash, $name) = @_;
	delete($modules{Compare}{defptr}{$hash->{DEF}}) if(defined($hash->{DEF}) && defined($modules{Compare}{defptr}{$hash->{DEF}}));
	return undef;
}

#####################################
sub Compare_Attr(@) {
	my ($cmd, $name, $attrName, $attrValue) = @_;
	my $hash = $defs{$name};
	
	if ($init_done == 1) {
		if ($cmd eq "set") {
		
		}
		##disabled?
		if ($attrName eq "disable"){
		
		}
    
    if ($attrName eq "disable"){
      
    }
		
		Log3 $name, 4, "$name: $cmd attr $attrName to $attrValue" if (defined $attrValue);
		Log3 $name, 4, "$name: $cmd attr $attrName" if (not defined $attrValue);
	}

	return undef;
}

#####################################
sub Compare_Set($@){
	my ($hash, @a) = @_;
	my $name = shift @a;
	#return undef if(IsDisabled($name) || !$init_done);
	#return "no set value specified" if(int(@a) < 1);

	my $cmd = shift @a;
	my $val = shift @a;
	
	if ($cmd eq "VisibleAdd"){
		my $Visible = ReadingsVal($name, "open", "");
		if ($Visible eq ""){
			$Visible = $val;
		} else {
			$Visible .= ",".$val;
		}
		
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash,"open",$Visible);
		readingsEndUpdate($hash,1);
	}
	if ($cmd eq "VisibleRemove"){
		my $Visible = ReadingsVal($name, "open", "");
		$Visible =~ s/$val//g;
		$Visible =~ s/,,/,/g;
		$Visible =~ s/^,//g;
		$Visible =~ s/,$//g;
		if ($Visible eq ","){
			readingsDelete($hash, "open");
		} else {
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash,"open",$Visible);
			readingsEndUpdate($hash,1);
		}
	}
		
	return;
}

#####################################
sub Compare_Notify($$){
	# $hash is my hash, $dev_hash is the hash of the changed device
	my ($hash, $dev_hash) = @_;
	my $events = deviceEvents($dev_hash,1);
	my $name   = $hash->{NAME};
	my $device = $dev_hash->{NAME};
	
	#use Data::Dumper;
	#my $ValDump = Dumper(\$events);
	#print "notify\n $name $device $ValDump\n";
	#print "$device\n";
	
	return undef if( !$events );
	return undef if (not defined $hash->{CompareDevices});
	
	#Attribute - global
	if ($device eq "global"){
		foreach my $event (@{$events}) {
			#print $event;
			#ATTR Max_HT_Bad_Unten alias fffrr
			if ("$event" =~ /^ATTR/) {
				my @e = split(" ", $event);
				next if (scalar @e < 4);
				shift @e; #erstes Element mit entfernen
				my $GlobalDevice = shift @e;
				my $Property = shift @e; 
				my $Value = join(":", @e);
				#Device	Property Value rai;
				#print ("$name $GlobalDevice $Property $Value $dev_hash->{NAME} \n");
				my $script="Comapre_Update('$GlobalDevice','$Property','$Value', 'a')";
				FW_directNotify("FILTER=$name", "#FHEMWEB:WEB", $script, "");
				#print ("$GlobalDevice','$Property','$Value', 'a'");
			}
		}
		return undef;
	}
	
	my @CompareDevices = split(",", $hash->{CompareDevices});
  push @CompareDevices, "global";
	my $IsMyDevice = 0;
  	
	for my $CDevice(@CompareDevices){
		if ($CDevice eq $device){
			$IsMyDevice = 1;
		}
	}
  #Log3 $name,3,"$name, $device IsmyDevice -> $IsMyDevice";
	
	return undef if ($IsMyDevice eq 0);
	
	foreach my $event (@{$events}) {
	  $event = "" if(!defined($event));
		next if ($event eq "");
		
		my @e = split(":", $event);
		next if (scalar @e < 2);
		my $Property = shift @e; #erstes Element mit entfernen
		my $Value = join(":", @e);
		
		#Device	Property Value rai;
		my $script="Comapre_Update('$device','$Property','$Value','r')";
		use Data::Dumper;
		my $ValDump = Dumper(\$events);
		#print ("$device $Property $Value $ValDump \n");
		FW_directNotify("FILTER=$name", "#FHEMWEB:WEB", $script, "");
		#print("'$device','$Property','$Value','r'");
  }
	
	#FW_directNotify("FILTER=$name", "#FHEMWEB:WEB", "location.reload('true')", "");
	return undef;
}

#####################################
sub Compare_summaryFn($$$$){
	my ($FW_wname, $d, $room, $pageHash) = @_;										# pageHash is set fosummaryFn.
	my $hash   = $defs{$d};
	my $name = $hash->{NAME};
	
  $hash->{ElementID}=0;
  
	#Einlesen der Devices
	#Devices aus der Definition übernehmen
	my $def=$hash->{DEF};
	my @defs = split("[ \t\n][ \t\n]*", $def);
	return "Definition error" if (scalar @defs	 == 0);
		
	my @CompareDevices;
  for my $i (0 .. $#defs){
	#for (my $i=0; $i < @defs; $i++) {
		#Devices suchen
		my @ar = devspec2array($defs[$i]);
    push @CompareDevices, @ar;
    #print join("\n",@CompareDevices);
    #print("\n ... \n");
  }
	
  $hash->{CompareDevices} = join(",", @CompareDevices);
  #notifyRegexpChanged($hash,join("|",@CompareDevices));
	#notifyRegexpChanged($hash,"global");
	my @notifyDev = @CompareDevices;
	push @notifyDev, "global";
	notifyRegexpChanged($hash,join("|",@notifyDev));
	$hash->{STATE} = "Compared ".scalar @CompareDevices	." devices";
	
  return "No Devices found." if (!@CompareDevices);
	return "No Devices found." if (scalar @CompareDevices	 == 0);
		
	my $HTML;
	
  $HTML =<<'EOF';
<style>
table.Compare, th.Compare, td.Compare
{
  border: 1px solid black;
  border-collapse: collapse;
}
th.Compare, td.Compare
{
  border: 1px solid black;
  border-collapse: collapse;
  padding: 5px;
  text-align: left;
}
tr.Compare_same, col.Compare_same{
  background-color: YellowGreen ;
}
tr.Compare_sameEmpty, col.Compare_sameEmpty{
  background-color: Yellow  ;
}
tr.Compare_different, col.Compare_different{
  background-color: LightCoral;
}
</style>
<script>
function Compare_ShowTextbox() {
	//#id Device rai reading
  var id = arguments[0];
  var Device = arguments[1];
  var rai = arguments[2];
  var reading = arguments[3];
	
	//Device contains "," -> mehrere Devices
	var multipleDevices = false;
	if (Device.indexOf(",") !== -1){
		multipleDevices = true;
	}
  
	var OldText = document.getElementById("CompareWert"+id).innerHTML;
	var txtbxText = OldText;
	if (multipleDevices){
		txtbxText = "";
	} else {
		txtbxText = txtbxText.replace("&nbsp;", " ");
		txtbxText = txtbxText.trim();
	}
  
	//Hinzufügen der Inputbox+Buttons
  document.getElementById("CompareEingabe"+id).innerHTML = //document.getElementById("Compare"+id).innerHTML+'<br>'+
      '<input type="text" id="CompareTXT'+id+'" name="first_name" value="'+txtbxText+'" />'+'<br>'+
      '<button id=CompareBtn1"'+id+'" onmouseup="Compare_NewText('+id+',1,\''+OldText+'\',\''+Device+'\',\''+rai+'\',\''+reading+'\')">OK</button>'+
      '<button id=CompareBtn2"'+id+'" onmouseup="Compare_NewText('+id+',2,\''+OldText+'\',\''+Device+'\',\''+rai+'\',\''+reading+'\')">Cancel</button>';
      
  document.getElementById("Compare"+id).removeAttribute("onclick");
};

function Compare_NewText() {
  var id = arguments[0];
  var OK = arguments[1];
  var Text = arguments[2];
  var Device = arguments[3];
  var rai = arguments[4];
  var reading = arguments[5];
	
  
  var cancel = false;
	
	//Device contains "," -> mehrere Devices
	var multipleDevices = false;
	if (Device.indexOf(",") !== -1){
		multipleDevices = true;
	}
  
  if (OK=="1"){
    var newText = document.getElementById("CompareTXT"+id).value;
    newText = newText.replace("&nbsp;", " ");
		newText = newText.trim();
    //Set command senden
    if (rai == "r"){
		if (newText==""){
			var r = confirm("Reading "+reading+" löschen?");
			if (r == true) {
				var command = "?cmd."+Device+"=deletereading "+Device+" "+reading;
				var retvalue = FW_cmd(FW_root+command, function(Data){});
			} else {
				//Nichts unternehmen!
				cancel = true;
			}
		} else {
			var command = "?cmd."+Device+"=setreading "+Device+" "+reading+" "+newText;
			var retvalue = FW_cmd(FW_root+command, function(Data){});
		}
	} 
    if (rai == "a"){
		if (newText==""){
			var r;
			if (multipleDevices){
				r = confirm("Attribut "+reading+" in allen Devices löschen?");
			} else {
				r = confirm("Attribut "+reading+" im Device "+Device+" löschen?");
			}
			
			if (r == true) {
				var command = "?cmd."+Device+"=deleteattr "+Device+" "+reading;
				var retvalue = FW_cmd(FW_root+command, function(Data){});
			} else {
				//Nichts unternehmen!
				cancel = true;
			}
		} else {
			var command = "?cmd."+Device+"=attr "+Device+" "+reading+" "+newText;
			var retvalue = FW_cmd(FW_root+command, function(Data){});
			
		}
    }
    if (cancel == false) {
			if (multipleDevices){
				//bleibt bestehen!
				//document.getElementById("Compare"+id).innerHTML = Text;
			} else {
				//Wird automatisch aktualisiert!
				//document.getElementById("Compare"+id).innerHTML = newText;
			}
			
	} else {
		//Abbrechen!
		//bleibt bestehen!
		//document.getElementById("Compare"+id).innerHTML = Text;
	}
	
    
  } else {
		//Abbrechen!!
		//bleibt bestehen!
    //document.getElementById("Compare"+id).innerHTML = Text;
  }
	
	//Ausblenden der Eingabefelder
	document.getElementById("CompareEingabe"+id).innerHTML = "";
    
  //Wird sofort wieder aufgerufen! onmouseup verwenden!
  document.getElementById("CompareWert"+id).setAttribute('onclick','Compare_ShowTextbox('+id+',\''+Device+'\',\''+rai+'\',\''+reading+'\')');
};

function Compare_SetDetailsView(){
	var Device = arguments[0];
	var number = arguments[1];
	
	var open = document.getElementById("CompareDetails"+number).open;
	var command = "";
	if (open == true){
		//wird geschlossen!
		command = "?cmd."+Device+"=set "+Device+" VisibleRemove "+number;
	} else {
		//wird geöffnet!
		command = "?cmd."+Device+"=set "+Device+" VisibleAdd "+number;
	}
	
	var retvalue = FW_cmd(FW_root+command, function(Data){});
	
	

};

function Comapre_Update(){
	var Device = arguments[0];
	var Property = arguments[1];
	var Value = arguments[2];
	var rai = arguments[3];
	
	var matches;
	if (rai == "a"){
		matches = document.querySelectorAll("[informid="+Device+"-a-"+Property+"]");
	} else {
		matches = document.querySelectorAll("[informid="+Device+"-"+Property+"]");
	}
	
	for (var item of matches) {
		var id = item.id;
		if (id != ""){
			document.getElementById(id).innerHTML = Value;
		}
	}
	
	
};
  
</script>

EOF

  my $TableFormat = AttrVal("$name", "TableFormat", "both");
  my $DetailsName1 = "";
  my $DetailsName2 = "";
  if ($TableFormat eq "both"){
    $DetailsName1 = " (Table format: Device)";
    $DetailsName2 = " (Table format: Readings)";
  }
  
  #DETAILS
  my @DEF = ("DEF");
	my $openStr = "";
	my @Opens = split(",", ReadingsVal("$name", "open", ""));
	
  if ($TableFormat eq "Devices" or $TableFormat eq "both"){
		if ( grep( /^1$/, @Opens ) ) {$openStr="open";} else {$openStr="";};
    $HTML .='<details id="CompareDetails1" '.$openStr.'><summary onmouseup="Compare_SetDetailsView(\''.$name.'\',1)">DEF'.$DetailsName1.'</summary><ul>';
    $HTML.=Compare_getHTML_Tbl_X($hash, \@DEF);
    $HTML.='</ul></details>';
  }
  if ($TableFormat eq "Readings" or $TableFormat eq "both"){
		if ( grep( /^2$/, @Opens ) ) {$openStr="open";} else {$openStr="";};
    $HTML .='<details id="CompareDetails2" '.$openStr.'><summary onmouseup="Compare_SetDetailsView(\''.$name.'\',2)">DEF'.$DetailsName2.'</summary><ul>';
    $HTML.=Compare_getHTML_Tbl_Y($hash, \@DEF);
    $HTML.='</ul></details>';
  }
    
  #INTERNALS
  if ($TableFormat eq "Devices" or $TableFormat eq "both"){
		if ( grep( /^3$/, @Opens ) ) {$openStr="open";} else {$openStr="";};
    $HTML .='<details id="CompareDetails3" '.$openStr.'><summary onmouseup="Compare_SetDetailsView(\''.$name.'\',3)">INTERNALS'.$DetailsName1.'</summary><ul>';
    $HTML.=Compare_getHTML_Tbl_X($hash, \@{Compare_getNames_INTERNALS($hash)});
    $HTML.='</ul></details>';
  }
  if ($TableFormat eq "Readings" or $TableFormat eq "both"){
		if ( grep( /^4$/, @Opens ) ) {$openStr="open";} else {$openStr="";};
    $HTML .='<details id="CompareDetails4" '.$openStr.'><summary onmouseup="Compare_SetDetailsView(\''.$name.'\',4)">INTERNALS'.$DetailsName2.'</summary><ul>';
    $HTML.=Compare_getHTML_Tbl_Y($hash, \@{Compare_getNames_INTERNALS($hash)});
    $HTML.='</ul></details>';
  }
      
  #HiddenInternals
  if ($TableFormat eq "Devices" or $TableFormat eq "both"){
		if ( grep( /^5$/, @Opens ) ) {$openStr="open";} else {$openStr="";};
    $HTML .='<details id="CompareDetails5" '.$openStr.'><summary onmouseup="Compare_SetDetailsView(\''.$name.'\',5)">HIDDEN-INTERNALS'.$DetailsName1.'</summary><ul>';
    $HTML.=Compare_getHTML_Tbl_X($hash, \@{Compare_getNames_HIDDENINTERNALS($hash)});
    $HTML.='</ul></details>';
  }
  if ($TableFormat eq "Readings" or $TableFormat eq "both"){
		if ( grep( /^6$/, @Opens ) ) {$openStr="open";} else {$openStr="";};
    $HTML .='<details id="CompareDetails6" '.$openStr.'><summary onmouseup="Compare_SetDetailsView(\''.$name.'\',6)">HIDDEN-INTERNALS'.$DetailsName2.'</summary><ul>';
    $HTML.=Compare_getHTML_Tbl_Y($hash, \@{Compare_getNames_HIDDENINTERNALS($hash)});
    $HTML.='</ul></details>';
  }
  
  #Readings
  if ($TableFormat eq "Devices" or $TableFormat eq "both"){
		if ( grep( /^7$/, @Opens ) ) {$openStr="open";} else {$openStr="";};
    $HTML .='<details id="CompareDetails7" '.$openStr.'><summary onmouseup="Compare_SetDetailsView(\''.$name.'\',7)">Readings'.$DetailsName1.'</summary><ul>';
    $HTML.=Compare_getHTML_Tbl_X($hash, \@{Compare_getNames_Readings($hash)});
    $HTML.='</ul></details>';
  }
  if ($TableFormat eq "Readings" or $TableFormat eq "both"){
		if ( grep( /^8$/, @Opens ) ) {$openStr="open";} else {$openStr="";};
    $HTML .='<details id="CompareDetails8" '.$openStr.'><summary onmouseup="Compare_SetDetailsView(\''.$name.'\',8)">Readings'.$DetailsName2.'</summary><ul>';
    $HTML.=Compare_getHTML_Tbl_Y($hash, \@{Compare_getNames_Readings($hash)});
    $HTML.='</ul></details>';
  }
  	
	#Attribute
  if ($TableFormat eq "Devices" or $TableFormat eq "both"){
		if ( grep( /^9$/, @Opens ) ) {$openStr="open";} else {$openStr="";};
    $HTML .='<details id="CompareDetails9" '.$openStr.'><summary onmouseup="Compare_SetDetailsView(\''.$name.'\',9)">Attribute'.$DetailsName1.'</summary><ul>';
    $HTML.=Compare_getHTML_Tbl_X($hash, \@{Compare_getNames_Attribute($hash)});
    $HTML.='</ul></details>';
  }
  if ($TableFormat eq "Readings" or $TableFormat eq "both"){
		if ( grep( /^10$/, @Opens ) ) {$openStr="open";} else {$openStr="";};
    $HTML .='<details id="CompareDetails10" '.$openStr.'><summary onmouseup="Compare_SetDetailsView(\''.$name.'\',10)">Attribute'.$DetailsName2.'</summary><ul>';
    $HTML.=Compare_getHTML_Tbl_Y($hash, \@{Compare_getNames_Attribute($hash)});
    $HTML.='</ul></details>';
  }
    
  #Vergleich
  my $v = AttrVal("$name", "Values", "");
  if (not $v eq ""){
    my @values = split(",", $v);
    
    if ($TableFormat eq "Devices" or $TableFormat eq "both"){
			if ( grep( /^11$/, @Opens ) ) {$openStr="open";} else {$openStr="";};
      $HTML .='<details id="CompareDetails11" '.$openStr.'><summary onmouseup="Compare_SetDetailsView(\''.$name.'\',11)">Values'.$DetailsName1.'</summary><ul>';
      $HTML.=Compare_getHTML_Tbl_X($hash, \@values); 
      $HTML.='</ul></details>';
    }
    if ($TableFormat eq "Readings" or $TableFormat eq "both"){
			if ( grep( /^12$/, @Opens ) ) {$openStr="open";} else {$openStr="";};
      $HTML .='<details open id="CompareDetails12" '.$openStr.'><summary onmouseup="Compare_SetDetailsView(\''.$name.'\',12)">Values'.$DetailsName2.'</summary><ul>';
      $HTML.=Compare_getHTML_Tbl_Y($hash, \@values);  
      $HTML.='</ul></details>';
    }
    
  }
	
  
  
  return $HTML;
  
}

#####################################
sub Compare_getNames_INTERNALS($){
  my $hash = shift;
	my @CompareDevices = split(",", $hash->{CompareDevices});
  
  my @names;
  
  foreach my $dev (@CompareDevices){
    my $Devhash = $defs{$dev};
    for my $key (keys %{$Devhash}) {
      #if ("i:$key" ~~ @names ){
      if ( grep( /^i:$key$/, @names ) ) {
        next;
      }
      if ("$key" eq "READINGS"){
        next;
      }
      if ("$key" eq "NAME"){
        next;
      }
      if ("$key" =~ /^\./) {
        next;
      }
      push @names, "i:$key";
    }
  }
  @names = sort @names;
  
  return \@names;
  
}

#####################################
sub Compare_getNames_HIDDENINTERNALS($){
  my $hash = shift;
	my @CompareDevices = split(",", $hash->{CompareDevices});
  
  my @names;
  
  foreach my $dev (@CompareDevices){
    my $Devhash = $defs{$dev};
    for my $key (keys %{$Devhash}) {
      if ( grep( /^i:$key$/, @names ) ) {
      #if ("i:$key" ~~ @names ){
        next;
      }
      if ("$key" eq ".userReadings"){
        next;
      }
      if ("$key" =~ /^\./) {
        push @names, "i:$key";
      }
    }
  }
  @names = sort @names;
  return \@names;
  
}

#####################################
sub Compare_getNames_Readings($){
  my $hash = shift;
	my @CompareDevices = split(",", $hash->{CompareDevices});
  
  my @names;
  
  foreach my $dev (@CompareDevices){
    my $Devhash = $defs{$dev};
    my $Readings = $Devhash->{READINGS};
    for my $key (keys %{$Readings}) {
      #if ("r:$key" ~~ @names ){
      if ( grep( /^r:$key$/, @names ) ) {
        next;
      }
      push @names, "r:$key";
    }
  }
  @names = sort @names;
  return \@names;
  
}

#####################################
sub Compare_getNames_Attribute($){
  my $hash = shift;
	my @CompareDevices = split(",", $hash->{CompareDevices});
  
  my @names;
  
  foreach my $dev (@CompareDevices){
    my $AttrHash = $attr{$dev};
    
    for my $key (keys %{$AttrHash}) {
      #if ("a:$key" ~~ @names ){
      if ( grep( /^a:$key$/, @names ) ) {
        next;
      }
      push @names, "a:$key";
    }
  }
  @names = sort @names;
  return \@names;
  
}

#####################################
#   |Dev1|Dev2
#v1 |    |
#v2 |    |
#r: = reading; a: = attribut; i=internal
sub Compare_getHTML_Tbl_X($$){
  my $hash = shift;
  my $n = shift;
  my @names = @{$n};
  my $name = $hash->{NAME};
  
  my @CompareDevices = split(",", $hash->{CompareDevices});
  
  my $HTML='<table class="Compare">';
	$HTML .= Compare_getHTML_Tr_Header($hash);
  
  
    
  foreach my $val (@names){
    my @Values;
		my @raiList;
    foreach my $dev (@CompareDevices){
      my $Wert;
      my $rai="";
      my $val2=$val;
      #welcher Wert? r: = reading; a: = attribut; i=internal
      if ("$val" =~ /^r:/) {
        $val2 = substr($val, 2, length($val)-2);
        $Wert = ReadingsVal("$dev", $val2, "&nbsp;");
        $rai = "r";
      } elsif ("$val" =~ /^a:/) {
        $val2 = substr($val, 2, length($val)-2);
        $Wert = AttrVal("$dev", $val2, "&nbsp;");
        $rai = "a";
      } elsif ("$val" =~ /^i:/) {
        $val2 = substr($val, 2, length($val)-2);
        $Wert = InternalVal("$dev", $val2, "&nbsp;");
        $rai = "i";
      } else {
        #r a i
        $Wert = ReadingsVal("$dev", $val, "&nbsp;");
        $rai = "r";
        if ($Wert eq "&nbsp;"){
          $Wert = AttrVal("$dev", $val, "&nbsp;");
          $rai = "a";
          if ($Wert eq "&nbsp;"){
            $Wert = InternalVal("$dev", $val, "&nbsp;");
            $rai = "i";
            if ($Wert eq "&nbsp;"){
              $rai = "";
            }
          }
        }
      }
      $val=$val2;
      push @Values, $Wert;
      push @raiList, $rai;
      
    }
    
    my $class=Compare_ClassNameRow($hash, \@Values);
    my $ID = $hash->{ElementID} +1;
		$hash->{ElementID} = $ID;
		my $raiRow = "";
		if (@raiList == grep { $_ eq "r" } @raiList) {
			#alle gleich
			$raiRow = "r";
		}
		if (@raiList == grep { $_ eq "a" } @raiList) {
			#alle gleich
			$raiRow = "a";
		}
		
		my $htmlstyle = 'style="cursor:pointer"';
		my $htmlId = 'id="Compare'.$ID.'"';
		my $htmlIdWert = 'id="CompareWert'.$ID.'"';
		my $htmlIdEingabe = 'id="CompareEingabe'.$ID.'"';
		my $htmlOnClick = 'onClick="Compare_ShowTextbox('.$ID.',\''.$hash->{CompareDevices}.'\',\''.$raiRow.'\',\''.$val.'\')" ';
		
		if ($raiRow eq "r" or $raiRow eq "a"){
			$HTML .= '<tr class="'.$class.'">';
			$HTML .= '<td class="Compare" '.$htmlId.' '.$htmlstyle.' >';
			$HTML .= '<div '.$htmlIdWert.' '.$htmlOnClick.' >'.$val.'</div>';
			$HTML .= '<div '.$htmlIdEingabe.'></div>';
			$HTML .= '</td>';
			#$HTML .= '<tr class="'.$class.'"><td style="cursor:pointer"  class="Compare" id="Compare'.$ID.'" onClick="Compare_ShowTextbox('.$ID.',\''.$hash->{CompareDevices}.'\',\''.$raiRow.'\',\''.$val.'\')">'.$val.'</td>';
		} else {
			$HTML .= '<tr class="'.$class.'">';
			$HTML .= '<td class="Compare" '.$htmlId.'>';
			$HTML .= '<div '.$htmlIdWert.'>'.$val.'</div>';
			$HTML .= '</td>';
			#$HTML .= '<tr class="'.$class.'"><td class="Compare" id="Compare'.$ID.'">'.$val.'</td>';
		}
    
    #foreach my $Val (@Values){
    for my $i (0 .. $#Values){
			$HTML .= Compare_getHTML_TD($hash, $Values[$i], $CompareDevices[$i], $raiList[$i], $val);
    }
    $HTML .= '</tr>';
  }
  $HTML .="</Table>";
    	
	return $HTML;
}

#####################################
# Table format Readings
#    | v1 | v2
#Dev1|    |
#Dev2|    |
#r: = reading; a: = attribut; i=internal
sub Compare_getHTML_Tbl_Y($$){
	my $hash = shift;
	my $n = shift;
	my @names = @{$n};
	my $name = $hash->{NAME};
	
	my @CompareDevices = split(",", $hash->{CompareDevices});

	#Erst Werte einlesen, damit verglichen werden kann!
	my @Spalten;
	my @Spaltenrai;
	
	#print @names;
	foreach my $val (@names){
		my @Werte;
		my @raiList;
		#print ("val: $val \n");
		my $val2=$val;
		foreach my $dev (@CompareDevices){
			my $Wert;
			my $rai="";
			$val2=$val;
			#welcher Wert? r: = reading; a: = attribut; i=internal
			if ("$val" =~ /^r:/) {
				$val2 = substr($val, 2, length($val)-2);
				$Wert = ReadingsVal("$dev", $val2, "&nbsp;");
				$rai = "r";
			} elsif ("$val" =~ /^a:/) {
				$val2 = substr($val, 2, length($val)-2);
				$Wert = AttrVal("$dev", $val2, "&nbsp;");
				$rai = "a";
			} elsif ("$val" =~ /^i:/) {
				$val2 = substr($val, 2, length($val)-2);
				$Wert = InternalVal("$dev", $val2, "&nbsp;");
				$rai = "i";
				#print ("rai=i\n");
			} else {
				#r a i
				$Wert = ReadingsVal("$dev", $val, "&nbsp;");
				$rai = "r";
				if ($Wert eq "&nbsp;"){
					$Wert = AttrVal("$dev", $val, "&nbsp;");
					$rai = "a";
					if ($Wert eq "&nbsp;"){
						$Wert = InternalVal("$dev", $val, "&nbsp;");
						$rai = "i";
						if ($Wert eq "&nbsp;"){
							$rai = "";
						}
					}
				}
			}
			push @Werte, $Wert;
			push @raiList, $rai;
		#print("$Wert  $rai  $val\n");
		}
		push @Spalten, \@Werte;
		push @Spaltenrai, \@raiList;
		$val=$val2;
	}

	#Formatierung
	my $HTML = '<table class="Compare"><colgroup><col></col>';
	foreach my $S(@Spalten){
		my @Spalte = @{$S};
		my $class=Compare_ClassNameRow($hash, \@Spalte);
		$HTML .= '<col class="'.$class.'" />';
	}
	$HTML .= '</colgroup>';
	
	#Überschriften
	$HTML .= '<tr class="Compare"><td class="Compare">Device</td>';
	#foreach my $val (@names){
	for my $x (0 .. $#names){
		
		#rai prüfen ob alles r oder abs
		my $rL = $Spaltenrai[$x];
		my @raiList1 = @{$rL}; 
		my $raiCol = "";
		if (@raiList1 == grep { $_ eq "r" } @raiList1) {
			#alle gleich
			$raiCol = "r";
		}
		if (@raiList1 == grep { $_ eq "a" } @raiList1) {
			#alle gleich
			$raiCol = "a";
		}
		
		#neue ID
		my $ID = $hash->{ElementID} +1;
		$hash->{ElementID} = $ID;
		
		my $htmlstyle = 'style="cursor:pointer"';
		my $htmlId = 'id="Compare'.$ID.'"';
		my $htmlIdWert = 'id="CompareWert'.$ID.'"';
		my $htmlIdEingabe = 'id="CompareEingabe'.$ID.'"';
		my $htmlOnClick = 'onClick="Compare_ShowTextbox('.$ID.',\''.$hash->{CompareDevices}.'\',\''.$raiCol.'\',\''.$names[$x].'\')" ';
		
		if ($raiCol eq "r" or $raiCol eq "a"){
			#'.$val.'</td>
			##id Device rai reading
			$HTML .= '<td class="Compare" '.$htmlId.' '.$htmlstyle.' >';
			$HTML .= '<div '.$htmlIdWert.' '.$htmlOnClick.' >'.$names[$x].'</div>';
			$HTML .= '<div '.$htmlIdEingabe.'></div>';
			$HTML .= '</td>';
			#$HTML .= '<td style="cursor:pointer"  class="Compare" id="Compare'.$ID.'" onClick="Compare_ShowTextbox('.$ID.',\''.$hash->{CompareDevices}.'\',\''.$raiCol.'\',\''.$names[$x].'\')">'.$names[$x].'</td>';
		} else {
			$HTML .= '<td class="Compare" '.$htmlId.'>';
			$HTML .= '<div '.$htmlIdWert.'>'.$names[$x].'</div>';
			$HTML .= '</td>';
			#$HTML .= '<td class="Compare">'.$names[$x].'</td>';
		}
		
		
	}
	$HTML .= '</tr>';

	#Werte
	for my $i (0 .. $#CompareDevices){
		$HTML .= '<tr><td class="Compare">'.$CompareDevices[$i].'</td>';
		for my $x (0 .. $#names){
			my $W = $Spalten[$x];
			my @w = @{$W};
			my $Wert = $w[$i];
		my $rL = $Spaltenrai[$x];
			my @raiList1 = @{$rL};
			my $rai = $raiList1[$i];
			#print ("$Wert - $CompareDevices[$i] - $rai - $names[$x] \n");
			$HTML .= Compare_getHTML_TD($hash, $Wert, $CompareDevices[$i], $rai, $names[$x]);
		}
	}
	
	$HTML .= '</tr>';
	$HTML .= '</table>';
	return $HTML;
}

#####################################
sub Compare_getHTML_TD($$$$$){
  my $hash = shift;
  my $Val = shift;
  my $Device = shift;
  my $rai = shift;
  my $ReadingName = shift;
  
  my $name = $hash->{NAME};
  
  my $ShowHash = AttrVal("$name", "ShowHASH", "0");
  
  my $ValDump = $Val;
  if ("$Val" =~ /^HASH/) {
      use Data::Dumper;
      $ValDump = Dumper(\%{$Val});
  }
  if ("$Val" =~ /^ARRAY/) {
      use Data::Dumper;
      $ValDump = Dumper($Val);
  }
  
  if ($ShowHash == 1){
      $Val = $ValDump;
  }
  my $ID = $hash->{ElementID} +1;
  $hash->{ElementID} = $ID;
	
	#informid erstellen
	my $informid;
	if ($rai eq "a"){
		$informid='informid="'.$Device.'-a-'.$ReadingName.'"';
	} else {
		$informid='informid="'.$Device.'-'.$ReadingName.'"';
	}
	
	my $htmlstyle = 'style="cursor:pointer"';
	my $htmlId = 'id="Compare'.$ID.'"';
	my $htmlIdWert = 'id="CompareWert'.$ID.'"';
	my $htmlIdEingabe = 'id="CompareEingabe'.$ID.'"';
	my $htmlOnClick = 'onClick="Compare_ShowTextbox('.$ID.',\''.$Device.'\',\''.$rai.'\',\''.$ReadingName.'\')" ';
	my $htmlTitle = 'title="'.$ValDump.'"';
	
  #Nur readings und Attribute sind änderbar!
  my $HTML;
  if ($rai eq "r" or $rai eq "a"){
		$HTML = '<td class="Compare" '.$htmlId.' '.$htmlstyle.' >';
		$HTML .= '<div '.$htmlIdWert.' '.$htmlOnClick.' '.$htmlTitle.' '.$informid.'>'.$Val.'</div>';
		$HTML .= '<div '.$htmlIdEingabe.'></div>';
		$HTML .= '</td>';
     #$HTML = '<td class="Compare" '.$informid.' style="cursor:pointer" id="Compare'.$ID.'" onClick="Compare_ShowTextbox('.$ID.',\''.$Device.'\',\''.$rai.'\',\''.$ReadingName.'\')" title="'.$ValDump.'">'.$Val.'</td>';
  } else {
		$HTML = '<td class="Compare" '.$htmlId.' >';
		$HTML .= '<div '.$htmlIdWert.' '.$htmlTitle.' '.$informid.'>'.$Val.'</div>';
		$HTML .= '</td>';
    #$HTML = '<td class="Compare" '.$informid.' id="Compare'.$ID.'" title="'.$ValDump.'">'.$Val.'</td>';
  }
  
  return $HTML;
  #'<td class="Compare" title="'.$ValDump.'">'.$Val.'</td>';
  
}

#####################################
# 0=unterschiedlich
# 1=gleich
# 2=gleich und leer
sub Compare_CompareRow($$){
  my $hash=shift;
  my $ValRef=shift;
  my @Values=@{$ValRef};
  return 1 if (scalar @Values	 == 0);
  return 1 if (scalar @Values	 == 1);
  for my $i (0 .. $#Values){
    if ($Values[$i] eq "&nbsp;"){
      $Values[$i] = "";
    }
  }
  
  my $same;
  my $sameWithEmpty=0;
  my $sameTXT=$Values[0];
  #Alle leer?
  my $alleLeer=1;
  for my $i (1 .. $#Values){
    #print $Values[$i];
    #print "\n";
    if ($Values[$i] ne ""){
      $alleLeer=0;
      last;
    }
  }
  if ($alleLeer ==1){
    #Alle gleich (wenn auch leer!)
    return 1;
  }
  
  for my $i (1 .. $#Values){
    if ($sameTXT eq ""){
      $sameTXT = $Values[$i];
      $sameWithEmpty=1;
    }
    if ($Values[$i] ne $sameTXT){
      if ($Values[$i] eq ""){
        $sameWithEmpty=1;
      } else {
        #Unterschiedlich!
        return 0;
      }
    }
  }
  if ($sameWithEmpty == 1){
    return 2;
  } else {
    return 1;
  }
    
}

#####################################
sub Compare_ClassNameRow($$){
  my $hash=shift;
  my $ValRef=shift;
  my @Values=@{$ValRef};
  
  my $Compare = Compare_CompareRow($hash, \@Values);
  
  my $class="";
    if ($Compare == 1){
      return "Compare_same";
    }
    if ($Compare == 2){
      return "Compare_sameEmpty";
    }
    if ($Compare == 0){
      return "Compare_different";
    }
}

#####################################
sub Compare_getHTML_Tr_Header($){
	my $hash = shift;
  my @CompareDevices = split(",", $hash->{CompareDevices});
	my $HTML='<tr class="Compare"><td class="Compare"></td>';
  foreach my $dev (@CompareDevices){
    #print $dev->{NAME};
		#$HTML .= "<td>$dev->{NAME}</td>"
    $HTML .='<td class="Compare">'.$dev.'</td>';
    #my $Devhash = $defs{$dev};
    #$HTML .= '<td class="Compare">'.$Devhash->{NAME}.'</td>';
	}
	
  return $HTML;
	
}



# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item [helper]
=item summary Compare internals, readings and attributes from multiple devices
=item summary_DE Vergleichen von Internals,Readings und Attributen von mehreren Geräten
=begin html

<a name="Compare"></a>
<h3>Compare</h3>


=end html

=begin html_DE

<a name="Compare"></a>
<h3>Compare</h3>
<div>
	<ul>
			<p>Das Modul Compare vergleicht Internals,Readings und Attribute von gewählten Geräten.</p>
      <p>Farben:<br>
				Grün = Alle Werte sind gleich
				Gelb = Alle Werte sind gleich, es sind jedoch auch leere (nicht vorhandene) Werte dabei
				Rot = Die Werte sind unterschiedlich
			</p>
			<h4>Beispiel:</h4>
			<p><code>define myCompare Compare WEB.*</code><br></p>
      
      <li><a name="Compare_Define"></a>
        <h4>Define</h4>
			<p><code>define &lt;NAME&gt; Compare WEB.*</code><br>
        Definition eines Compare Moduls mit allen WEB-Devices von FHEM.<br>
      </p>
			<p><code>define &lt;NAME&gt; Compare TYPE=MAX</code><br>
        Definition eines Compare Moduls mit allen MAX Devices.<br>
			</p>
      </li>
	</ul>
  
  <h4>Attributes</h4>
  <ul><a name="Compare_Attr"></a>
		<li><a name="ShowHASH">ShowHASH</a><br>
			<code>attr &lt;Compare-Device&gt; ShowHASH &lt;0|1&gt;</code><br>
            HASH-Werte vollständig in der Tabelle anzeigen. (Sonst nur per ToolTip verfügbar)<br>
    </li>
    <li><a name="TableFormat">TableFormat</a><br>
			<code>attr &lt;Compare-Device&gt; TableFormat &lt;Devices|Readings|both&gt;</code><br>
            Anzeige Devices:<br>
            <table>
            <tr><td></td><td>Device1&nbsp;&nbsp;&nbsp;</td><td>Device2&nbsp;&nbsp;&nbsp;</td><td>Device3&nbsp;&nbsp;&nbsp;</td><td>DeviceX</td></tr>
            <tr><td>Reading1&nbsp;&nbsp;&nbsp;</td><td>Value</td><td>Value</td><td>Value</td><td>Value</td></tr>
            <tr><td>Reading2&nbsp;&nbsp;&nbsp;</td><td>Value</td><td>Value</td><td>Value</td><td>Value</td></tr>
            <tr><td>ReadingX&nbsp;&nbsp;&nbsp;</td><td>Value</td><td>Value</td><td>Value</td><td>Value</td></tr>
            </table><br>
            Anzeige Readings:<br>
            <table>
            <tr><td></td><td>Reading1&nbsp;&nbsp;&nbsp;</td><td>Reading2&nbsp;&nbsp;&nbsp;</td><td>Reading3&nbsp;&nbsp;&nbsp;</td><td>ReadingX</td></tr>
            <tr><td>Device1&nbsp;&nbsp;&nbsp;</td><td>Value</td><td>Value</td><td>Value</td><td>Value</td></tr>
            <tr><td>Device2&nbsp;&nbsp;&nbsp;</td><td>Value</td><td>Value</td><td>Value</td><td>Value</td></tr>
            <tr><td>DeviceX&nbsp;&nbsp;&nbsp;</td><td>Value</td><td>Value</td><td>Value</td><td>Value</td></tr>
            </table><br>
            Anzeige both:<br>
            Beide Tabellen werden angezeigt.<br>
    </li>
    <li><a name="Values">Values</a><br>
			<code>attr &lt;Compare-Device&gt; Values &lt;Readings|Attribute|Internals&gt;</code><br>
            Auflistung von Internals, Readings oder Attributen, die in einer extra Tabelle angezeigt werden sollen.<br>
            Um gleichnamige zu unterscheiden, kann ein Praefix (i: für internal Werte, r: für Reading-Namen und a: für Attribute) verwendet werden.<br>
            Beispiel:<br>
            <code>attr &lt;Compare-Device&gt; Values DEF,userattr,a:icon,r:RSSI</code><br>
    </li>
  </ul>
    
</div>

=end html_DE

=cut



