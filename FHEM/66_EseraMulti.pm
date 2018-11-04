################################################################################
# 66_EseraMulti.pm 
################################################################################
#
# Copyright pizmus 2018
#
# This FHEM module supports an Esera multi sensor connected via
# an Esera "1-wire Controller 1" with LAN interface and the 66_EseraOneWire 
# module.
#
# supported device types: DS2438, 11134 (Esera multi sensor)
#
################################################################################

package main;

use strict;
use warnings;
use SetExtensions;

sub 
EseraMulti_Initialize($) 
{
  my ($hash) = @_;
  $hash->{Match}         = "DS2438";
  $hash->{DefFn}         = "EseraMulti_Define";
  $hash->{UndefFn}       = "EseraMulti_Undef";
  $hash->{ParseFn}       = "EseraMulti_Parse";
  $hash->{SetFn}         = "EseraMulti_Set";
  $hash->{GetFn}         = "EseraMulti_Get";
  $hash->{AttrFn}        = "EseraMulti_Attr";
  $hash->{AttrList}      = "$readingFnAttributes";
}

sub 
EseraMulti_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split( "[ \t][ \t]*", $def);
  
  return "Usage: define <name> EseraMulti <physicalDevice> <1-wire-ID> <deviceType>" if(@a < 5);

  my $devName = $a[0];
  my $type = $a[1];
  my $physicalDevice = $a[2];
  my $oneWireId = $a[3];
  my $deviceType = uc($a[4]);

  $hash->{STATE} = 'Initialized';
  $hash->{NAME} = $devName;
  $hash->{TYPE} = $type;
  $hash->{ONEWIREID} = $oneWireId;
  $hash->{ESERAID} = undef;  # We will get this from the first reading.
  $hash->{DEVICE_TYPE} = $deviceType;

  $modules{EseraMulti}{defptr}{$oneWireId} = $hash;
  
  AssignIoPort($hash, $physicalDevice);
  
  if (defined($hash->{IODev}->{NAME})) 
  {
    Log3 $devName, 4, "$devName: I/O device is " . $hash->{IODev}->{NAME};
  } 
  else 
  {
    Log3 $devName, 1, "$devName: no I/O device";
  }

  # program the the device type into the controller via the physical module
  if ($deviceType =~ m/^DS([0-9A-F]+)/)
  {
    # for the DS* devices types the "DS" has to be omitted
    IOWrite($hash, "assign;$oneWireId;$1");
  }
  else
  {
    IOWrite($hash, "assign;$oneWireId;$deviceType");
  }
    
  return undef;
}

sub 
EseraMulti_Undef($$) 
{
  my ($hash, $arg) = @_;  
  my $oneWireId = $hash->{ONEWIREID};
  
  RemoveInternalTimer($hash);
  delete( $modules{EseraMulti}{defptr}{$oneWireId} );
  
  return undef;
}

sub 
EseraMulti_Get($@) 
{
  return undef;
}

sub 
EseraMulti_Set($$) 
{
  my ( $hash, @parameters ) = @_;
  my $name = $parameters[0];
  my $what = lc($parameters[1]);
 
  my $oneWireId = $hash->{ONEWIREID};
  my $iodev = $hash->{IODev}->{NAME};
  
  my $commands = ("statusRequest");
  
  if ($what eq "statusRequest")
  {
    IOWrite($hash, "status;$oneWireId");
  }
  elsif ($what eq "?")
  {
    # TODO use the :noArg info 
    my $message = "unknown argument $what, choose one of $commands";
    return $message;
  }
  else
  {
    my $message = "unknown argument $what, choose one of $commands";
    Log3 $name, 1, "EseraMulti ($name) - ".$message;
    return $message;
  }
  return undef;
}

sub 
EseraMulti_Parse($$) 
{
  my ($ioHash, $msg) = @_;
  my $ioName = $ioHash->{NAME};
  my $buffer = $msg;

  # expected message format: $deviceType."_".$oneWireId."_".$eseraId."_".$readingId."_".$value
  my @fields = split(/_/, $buffer);
  if (scalar(@fields) != 5)
  {
    return undef;
  }
  my $deviceType = uc($fields[0]);
  my $oneWireId = $fields[1];
  my $eseraId = $fields[2];
  my $readingId = $fields[3];
  my $value = $fields[4];

  # search for logical device
  my $rhash = undef;  
  foreach my $d (keys %defs) {
    my $h = $defs{$d};
    my $type = $h->{TYPE};
        
    if($type eq "EseraMulti") 
    {
      if (defined($h->{IODev}->{NAME})) 
      {
        my $ioDev = $h->{IODev}->{NAME};
        my $def = $h->{DEF};

        # $def has the whole definition, extract the oneWireId (which is expected as 2nd parameter)
        my @parts = split(/ /, $def);
	my $oneWireIdFromDef = $parts[1];

        if (($ioDev eq $ioName) && ($oneWireIdFromDef eq $oneWireId)) 
	{
          $rhash = $h;
          last;
        }
      }
    }
  }
 
  if($rhash) {
    my $rname = $rhash->{NAME};
    Log3 $rname, 4, "EseraMulti ($rname) - parse - device found: ".$rname;

    # capture the Esera ID for later use
    $rhash->{ESERAID} = $eseraId;
    
    # consistency check of device type
    if (!($rhash->{DEVICE_TYPE} eq uc($deviceType)))
    {
      Log3 $rname, 1, "EseraMulti ($rname) - unexpected device type ".$deviceType;
      
      # program the the device type into the controller via the physical module
      if ($rhash->{DEVICE_TYPE} =~ m/^DS([0-9A-F]+)/)
      {
        # for the DS* devices types the "DS" has to be omitted
        IOWrite($rhash, "assign;$oneWireId;$1");
      }
      else
      {
        IOWrite($rhash, "assign;$oneWireId;".$rhash->{DEVICE_TYPE});
      }
    }
    
    if ($readingId eq "ERROR")
    {
      Log3 $rname, 1, "EseraMulti ($rname) - error message from physical device: ".$value;
    }
    elsif ($readingId eq "STATISTIC")
    {
      Log3 $rname, 1, "EseraMulti ($rname) - statistics message not supported yet: ".$value;
    }
    else
    {
      my $nameOfReading = $oneWireId."_";
      if ($deviceType eq "DS2438")
      {
        if ($readingId == 1) 
        {
          $nameOfReading .= "temperature";
          readingsSingleUpdate($rhash, $nameOfReading, $value / 100.0, 1);
        }
        elsif ($readingId == 2) 
        {
          $nameOfReading .= "VCC";
          readingsSingleUpdate($rhash, $nameOfReading, $value / 100.0, 1);
        }
        elsif ($readingId == 3) 
        {
          $nameOfReading .= "VAD";
          readingsSingleUpdate($rhash, $nameOfReading, $value / 100.0, 1);
        }
        elsif ($readingId == 4) 
        {
          $nameOfReading .= "VSense";
          readingsSingleUpdate($rhash, $nameOfReading, $value / 100000.0, 1);
        }
      }
      elsif ($deviceType eq "11134")
      {
        if ($readingId == 1) 
        {
          $nameOfReading .= "temperature";
          readingsSingleUpdate($rhash, $nameOfReading, $value / 100.0, 1);
        }
        elsif ($readingId == 2) 
        {
          $nameOfReading .= "voltage";
          readingsSingleUpdate($rhash, $nameOfReading, $value / 100.0, 1);
        }
        elsif ($readingId == 3) 
        {
          $nameOfReading .= "humidity";
          readingsSingleUpdate($rhash, $nameOfReading, $value / 100.0, 1);
        }
        elsif ($readingId == 4) 
        {
          $nameOfReading .= "dewpoint";
          readingsSingleUpdate($rhash, $nameOfReading, $value / 100.0, 1);
        }
        elsif ($readingId == 5) 
        {
          $nameOfReading .= "brightness";
          readingsSingleUpdate($rhash, $nameOfReading, $value / 100.0, 1);
        }
      }      
    }
           
    my @list;
    push(@list, $rname);
    return @list;
  }
  elsif ($deviceType eq "DS2438")
  {
    return "UNDEFINED EseraMulti_".$ioName."_".$oneWireId." EseraMulti ".$ioName." ".$oneWireId." ".$deviceType;
  }
  
  return undef;
}

sub 
EseraMulti_Attr(@) 
{
}

1;

=pod
=item summary    Represents an Esera 1-wire multi sensor.
=item summary_DE Repraesentiert einen Esera 1-wire Multi-Sensor.
=begin html

<a name="EseraMulti"></a>
<h3>EseraMulti</h3>

<ul>
  This module supports an Esera 1-wire multi sensor or a DS2438 1-wire IC.<br>
  It uses 66_EseraOneWire as I/O device.<br>
  <br>
  
  <a name="EseraMulti_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EseraMulti &lt;ioDevice&gt; &lt;oneWireId&gt; &lt;deviceType&gt;</code><br>
    &lt;oneWireId&gt; specifies the 1-wire ID of the sensor. Use the "get devices" <br>
    query of EseraOneWire to get a list of 1-wire IDs, or simply rely on autocreate. <br>
    Supported values for deviceType: 
    <ul>
      <li>11134 (Esera product number)</li>
      <li>DS2438 (1-wire chip used by 11134)</li>
    </ul>
    With deviceType DS2438 this device generates readings with un-interpreted data<br>
    from DS2438. This can be used with any DS2438 device, independent of an Esera <br>
    product. With deviceType 11134 this module provides interpreted readings like <br>
    humidity or dew point.<br>
  </ul>
  
  <a name="EseraMulti_Set"></a>
  <b>Set</b>
  <ul>
    <li>no get functionality</li>
  </ul>
  <br>

  <a name="EseraMulti_Get"></a>
  <b>Get</b>
  <ul>
    <li>no get functionality</li>
  </ul>
  <br>

  <a name="EseraMulti_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>no attributes</li>
  </ul>
  <br>
      
  <a name="EseraMulti_Readings"></a>
  <b>Readings</b>
  <ul>
    readings for DS2438:<br>
    <ul>
      <li>&lt;oneWireId&gt;_VAD</li>
      <li>&lt;oneWireId&gt;_VCC</li>
      <li>&lt;oneWireId&gt;_VSense</li>
      <li>&lt;oneWireId&gt;_temperature</li>
    </ul>
    readings for Esera 11134:<br>
    <ul>
      <li>&lt;oneWireId&gt;_temperature</li>
      <li>&lt;oneWireId&gt;_humidity</li>
      <li>&lt;oneWireId&gt;_dewpoint</li>
      <li>&lt;oneWireId&gt;_brightness</li>
      <li>&lt;oneWireId&gt;_voltage</li>
    </ul>
  </ul>
  <br>

</ul>

=end html
=cut
