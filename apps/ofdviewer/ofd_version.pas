unit ofd_version;
{$mode objfpc}{$H+}
{ Single source of truth for the application version.
  When bumping: update OFD_APP_VERSION here, and keep the Win32 version
  resource (apps/ofdviewer/ofdviewer.rc) in sync. The release scripts read
  this unit to name the portable zip. }

interface

const
  OFD_APP_VERSION = '0.0.3';

implementation

end.
