#!/usr/bin/python

import xmlrpclib
import sys
server = xmlrpclib.ServerProxy('http://127.0.0.1/xmlrpc.cgi')
try:
    result = server.GNOME.addversionx({'product': 'lalala', 'version': '1.2.3.4'})
except xmlrpclib.Fault, e:
    print "FAILED (%s)" % e.faultString
    sys.exit(1)
except Exception, e:
    print "FAILED (%s)" % e.strerror
    sys.exit(1)
else:
    print result
    sys.exit(0)
