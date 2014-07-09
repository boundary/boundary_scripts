#!/usr/bin/python

import sys
import json
import urllib2
import base64
import os

__all__ = [ 'main', ]

# Use environment variables if set other set to empty
API_KEY=os.environ['BOUNDARY_API_KEY']
ORG_ID=os.environ['BOUNDARY_ORG_ID']
API_URL="https://api.boundary.com/" + ORG_ID + "/events"

def encode_bn_auth():
    b64_auth = base64.encodestring( ':'.join([API_KEY, ''])).replace('\n', '')
    return ' '.join(['Basic', b64_auth])

#Query ORG for Events
def get_events(auth_header):
    #url = '/'.join([API_URL, ORG_ID, E_QUERY])
    #print "query url >>>" + url + "<<<"
    #print "API_URL >>>" + API_URL + "<<<"

    req = urllib2.Request(API_URL)
    req.add_header('Authorization',auth_header)
    response = urllib2.urlopen(req)
    events = json.load(response)

    return events

def delete_event(eventid):
	os.system("/usr/bin/curl -X DELETE -i -u " + API_KEY + ": " + API_URL + "/" + eventid)
	print "Event matching id >>>" + eventid + "<<< has been DELETED"
	#url = API_URL + "/" + eventid
    #req = urllib2.Request(url, {'Content-type': 'application/json'})
    #req.add_header('Authorization', auth_header)
    #response = urllib2.urlopen(req)

#Loop through events and delete each one
def main():
    bn_auth_header = encode_bn_auth()
    #get_events(bn_auth_header)

    events = get_events(bn_auth_header)
    eventcount = events["total"]
    print "Event count is >>>" + str(eventcount) + "<<<"

    while eventcount > 0:
		for event in events["results"]:
			eventid = str(event["id"])
			delete_event(eventid)

		events = get_events(bn_auth_header)
		eventcount = events["total"]
		print "Event count is >>>" + str(eventcount) + "<<<"

if __name__ == "__main__":
    main()
