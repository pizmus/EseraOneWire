################################################################################
#
#    66_EseraShutter.pm
#
#    Copyright (C) 2019  pizmus
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
################################################################################
#
# This FHEM module controls an Esera shutter device connected via
# an Esera 1-wire Controller and the 66_EseraOneWire module.
#
################################################################################

package main;

use strict;
use warnings;
use SetExtensions;

my $ESERA_SHUTTER_COMMAND_DOWN = 1;
my $ESERA_SHUTTER_COMMAND_UP = 2;
my $ESERA_SHUTTER_COMMAND_STOP = 3;

sub
EseraShutter_Initialize($)
{
  my ($hash) = @_;
  $hash->{Match}         = "11209|11231";
  $hash->{DefFn}         = "EseraShutter_Define";
  $hash->{UndefFn}       = "EseraShutter_Undef";
  $hash->{ParseFn}       = "EseraShutter_Parse";
  $hash->{SetFn}         = "EseraShutter_Set";
  $hash->{GetFn}         = "EseraShutter_Get";
  $hash->{AttrFn}        = "EseraShutter_Attr";
  $hash->{AttrList}      = "$readingFnAttributes";
}

sub
EseraShutter_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split( "[ \t][ \t]*", $def);

  return "Usage: define <name> EseraShutter <physicalDevice> <1-wire-ID> <deviceType>" if(@a < 5);

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

  $modules{EseraShutter}{defptr}{$oneWireId} = $hash;

  AssignIoPort($hash, $physicalDevice);

  if (defined($hash->{IODev}->{NAME}))
  {
    Log3 $devName, 4, "EseraShutter ($devName) - I/O device is " . $hash->{IODev}->{NAME};
  }
  else
  {
    Log3 $devName, 1, "EseraShutter ($devName) - no I/O device";
  }

  if (($deviceType == 11209) || ($deviceType == 11231))
  {
    IOWrite($hash, "assign;$oneWireId;$deviceType");
  }
  else
  {
    Log3 $devName, 1, "EseraShutter ($devName) - deviceType ".$deviceType." is not supported";
  }

  return undef;
}

sub
EseraShutter_Undef($$)
{
  my ($hash, $arg) = @_;
  my $oneWireId = $hash->{ONEWIREID};

  RemoveInternalTimer($hash);
  delete( $modules{EseraShutter}{defptr}{$oneWireId} );

  return undef;
}

sub
EseraShutter_Get($@)
{
  return undef;
}

sub
EseraShutter_sendDownUpStopCommand($$$)
{
  my ($hash, $oneWireId, $commandCode) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "EseraShutter ($name) - EseraShutter_sendDownUpStopCommand: $oneWireId,$commandCode";

  if (!defined  $hash->{DEVICE_TYPE})
  {
    my $message = "error: device type not known";
    Log3 $name, 1, "EseraShutter ($name) - ".$message;
    return $message;
  }

  if (($hash->{DEVICE_TYPE} eq "11209") ||
      ($hash->{DEVICE_TYPE} eq "11231"))
  {
    if (($commandCode < ESERA_SHUTTER_COMMAND_DOWN) || ($commandCode > ESERA_SHUTTER_COMMAND_STOP))
    {
      my $message = "error: unknown commandCode";
      Log3 $name, 1, "EseraShutter ($name) - ".$message;
      return $message;
    }

    # look up the ESERA ID
    my $eseraId = $hash->{ESERAID};
    if (!defined $eseraId)
    {
      my $message = "error: ESERA ID not known";
      Log3 $name, 1, "EseraShutter ($name) - ".$message;
      return $message;
    }

    # set output
    my $command = "set,owd,sht,".$eseraId.",".$commandCode;
    IOWrite($hash, "set;$eseraId;$command");
  }
  else
  {
    my $message = "error: device type not supported: ".$hash->{DEVICE_TYPE};
    Log3 $name, 1, "EseraShutter ($name) - ".$message;
    return $message;
  }

  return undef;
}

sub
EseraShutter_Set($$)
{
  my ( $hash, @parameters ) = @_;
  my $name = $parameters[0];
  my $what = lc($parameters[1]);

  my $oneWireId = $hash->{ONEWIREID};
  my $iodev = $hash->{IODev}->{NAME};

  my $commands = ("up:noArg down:noArg stop:noArg");

  if ($what eq "down")
  {
    if ((scalar(@parameters) != 2))
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).")";
      Log3 $name, 1, "EseraShutter ($name) - ".$message;
      return $message;
    }
    EseraShutter_sendDownUpStopCommand($hash, $oneWireId, ESERA_SHUTTER_COMMAND_DOWN);
  }
  elsif ($what eq "up")
  {
    if ((scalar(@parameters) != 2))
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).")";
      Log3 $name, 1, "EseraShutter ($name) - ".$message;
      return $message;
    }
    EseraShutter_sendDownUpStopCommand($hash, $oneWireId, ESERA_SHUTTER_COMMAND_UP);
  }
  elsif ($what eq "stop")
  {
    if ((scalar(@parameters) != 2))
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).")";
      Log3 $name, 1, "EseraShutter ($name) - ".$message;
      return $message;
    }
    EseraShutter_sendDownUpStopCommand($hash, $oneWireId, ESERA_SHUTTER_COMMAND_STOP);
  }
  elsif ($what eq "?")
  {
    my $message = "unknown argument $what, choose one of $commands";
    return $message;
  }
  else
  {
    shift @parameters;
    shift @parameters;
    return SetExtensions($hash, $commands, $name, $what, @parameters);
  }
  return undef;
}

sub
EseraShutter_ParseForOneDevice($$$$$$)
{
  my ($rhash, $deviceType, $oneWireId, $eseraId, $readingId, $value) = @_;
  my $rname = $rhash->{NAME};
  Log3 $rname, 4, "EseraShutter ($rname) - ParseForOneDevice: ".$rname;

  # capture the Esera ID for later use
  $rhash->{ESERAID} = $eseraId;

  # consistency check of device type
  if (!($rhash->{DEVICE_TYPE} eq uc($deviceType)))
  {
    Log3 $rname, 1, "EseraShutter ($rname) - unexpected device type ".$deviceType;

    # program the the device type into the controller via the physical module
    IOWrite($rhash, "assign;$oneWireId;".$rhash->{DEVICE_TYPE});
  }

  if ($readingId eq "ERROR")
  {
    Log3 $rname, 1, "EseraShutter ($rname) - error message from physical device: ".$value;
  }
  elsif ($readingId eq "STATISTIC")
  {
    Log3 $rname, 1, "EseraShutter ($rname) - statistics message not supported yet: ".$value;
  }
  else
  {
    my $nameOfReading;
    if (($deviceType eq "11209") || ($deviceType eq "11231"))
    {
      # TODO Documentation of readings in Esera manual seems wrong. Learn from Esera support about readings.
      #      For now assume there are 4 readings. Pass them to the user as is.
      if ($readingId == 1)
      {
        $nameOfReading = "reading1";
        readingsSingleUpdate($rhash, $nameOfReading, $value, 1);
      }
      elsif ($readingId == 2)
      {
        $nameOfReading = "reading2";
        readingsSingleUpdate($rhash, $nameOfReading, $value, 1);
      }
      elsif ($readingId == 3)
      {
        $nameOfReading = "reading3";
        readingsSingleUpdate($rhash, $nameOfReading, $value, 1);
      }
      elsif ($readingId == 4)
      {
        $nameOfReading = "readings4";
        readingsSingleUpdate($rhash, $nameOfReading, $value, 1);
      }
    }
  }
  return $rname;
}

sub
EseraShutter_Parse($$)
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
  my @list;
  foreach my $d (keys %defs)
  {
    my $h = $defs{$d};
    my $type = $h->{TYPE};

    if($type eq "EseraShutter")
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
	  my $rname = EseraShutter_ParseForOneDevice($rhash, $deviceType, $oneWireId, $eseraId, $readingId, $value);
          push(@list, $rname);
        }
      }
    }
  }

  if ((scalar @list) > 0)
  {
    return @list;
  }
  elsif (($deviceType eq "11209") or ($deviceType eq "11231"))
  {
    return "UNDEFINED EseraShutter_".$ioName."_".$oneWireId." EseraShutter ".$ioName." ".$oneWireId." ".$deviceType;
  }

  return undef;
}

sub
EseraShutter_Attr(@)
{
}

1;

=pod
=item summary    Represents an Esera 1-wire shutter device.
=item summary_DE Repraesentiert einen Esera 1-wire Shutter.
=begin html
<a name="EseraShutter"></a>
<h3>EseraShutter</h3>
<ul>
  This module implements an Esera 1-wire shutter. It uses 66_EseraOneWire as I/O device.<br>
  NOTE: The module is not yet tested with real hardware. Known issues: Names of readings are<br>
  not correct yet. Autocreate is not expected to work yet, unless the shutter has an<br>
  Esera product number assigned in the Esera controller.<br>
  <br>

  <a name="EseraShutter_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EseraShutter &lt;ioDevice&gt; &lt;oneWireId&gt; &lt;deviceType&gt;</code><br>
    &lt;oneWireId&gt; specifies the 1-wire ID of the shutter device.<br>
    Use the "get devices" query of EseraOneWire to get a list of 1-wire IDs, <br>
    or simply rely on autocreate.<br>
    Supported values for deviceType:
    <ul>
      <li>11209</li>
      <li>11231</li>
    </ul>
  </ul>
  <br>

  <a name="EseraShutter_Set"></a>
  <b>Set</b>
  <ul>
    <li>
      <b><code>set &lt;name&gt; down</code><br></b>
    </li>
    <li>
      <b><code>set &lt;name&gt; up</code><br></b>
    </li>
    <li>
      <b><code>set &lt;name&gt; stop</code><br></b>
    </li>
  </ul>
  <br>
  <a name="EseraShutter_Get"></a>
  <b>Get</b>
  <ul>
    <li>no get functionality</li>
  </ul>
  <br>
  <a name="EseraShutter_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>no attributes</li>
  </ul>
  <br>

  <a name="EseraShutter_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>reading1 &ndash; ??? TODO</li>
    <li>reading2 &ndash; ??? TODO</li>
    <li>reading3 &ndash; ??? TODO</li>
    <li>reading4 &ndash; ??? TODO</li>
  </ul>
  <br>
</ul>
=end html
=cut
