tempest - log and present WeatherFlow Tempest weather station data
==================================================================

This program runs in the background and listens for UDP broadcast events
from a WeatherFlow Tempest weather station. It collects and records a subset
of the data, recording the data in a tab-separated timeseries data file, and
keeping a JSON file up to date with the most recent state. That JSON file
can be used in turn to answer REST API requests for upstream systems.

Usage
-----

For usage:

    % tempest -h

Output tab-separated timeseries data to STDOUT and diagnostic logs to STDERR:

    % tempest

Output diagnostic logs, tab-separated timeseries data, and a current state
in JSON to named filesystem locations:

    % tempest -o program.log -d data.txt -s /htdocs/data.json

On a host protected by a firewall, you may need to allow UDP broadcast.
For the `iptables` software firewall, one invocation is:

    % iptables -I INPUT -p udp -m pkttype --pkt-type broadcast -j ACCEPT

There is also a simple `tempest_dump` script with the simplest possible
example of listening for the UDP broadcast packets.

This program requires Ruby and uses only Ruby standard library modules;
it should run out of the box on most MacOS or Linux distributions.

References
----------

* [Tempest API docs](https://weatherflow.github.io/Tempest/api/udp/v143/)

Author
------

Andrew Ho <andrew@zeuscat.com>

License
-------

WeatherFlow and Tempest are registered trademarks of WeatherFlow-Tempest,
Inc. WeathrFlow-Tempest, Inc. does not sponsor, authorize, or endorse this
codebase. The files in this repository are authored by Andrew Ho, and are
covered by the following MIT license:

    Copyright 2021-2022 Andrew Ho
    
    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"),
    to deal in the Software without restriction, including without limitation
    the rights to use, copy, modify, merge, publish, distribute, sublicense,
    and/or sell copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following conditions:
    
    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.
    
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
    THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    DEALINGS IN THE SOFTWARE.
