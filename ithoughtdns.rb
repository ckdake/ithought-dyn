require 'rubygems'
require 'dynect_rest'

#config.rb contains config values. example:
# ACCOUNT = "demo-demo"
# USER = "demo"
# PASS = "demo"
# SOACONTACT = "admin.demo"
require 'config.rb'

#zones.rb contains a hash of hashes of information about domains.  example:
#  ZONES = {
#   'example.com' => { 'mail' => 'ithought', 'web' => 'pongo' },
#   'example2.com' => { 'mail' => 'google', 'web' => 'pongo' },
#  }
require 'zones.rb'

dyn = DynectRest.new(ACCOUNT, USER, PASS)

ZONES.map { |zone,attributes|
  arecords = {}
  cnamerecords = {}

  # verify exists in DYN, add if new
  begin
    record = dyn.get('Zone/' + zone) 
  rescue DynectRest::Exceptions::RequestFailed => e
    record = dyn.post('Zone/' + zone, {"rname" => SOACONTACT, "ttl" => 7200, "zone" => zone})
  end

  # verify SOA, correct if wrong
  dyn.get('SOARecord/' + zone + '/' + zone + '/').map { |soaid| 
    soaid.gsub!('/REST/SOARecord/' + zone + '/' + zone + '/', '')
    rdata = dyn.get('SOARecord/' + zone + '/' + zone + '/' + soaid)['rdata']
    if rdata['rname']  != SOACONTACT + '.'
      print zone + " has invalid SOA Contact: " + rdata['rname'] + ": fixing!\n"
      dyn.put('SOARecord/' + zone + '/' + zone + '/' + soaid, {"rdata" => { "rname" => SOACONTACT } })
    end
  }

  # verify NS, correct if wrong
  nsentries = ["ns1.p09.dynect.net.", "ns2.p09.dynect.net.", "ns3.p09.dynect.net.", "ns4.p09.dynect.net."]
  livensentries = []
  dyn.get('NSRecord/' + zone + '/' + zone + '/').map { |nsid|
    nsid.gsub!('/REST/NSRecord/' + zone + '/' + zone + '/', '')
    rdata = dyn.get('NSRecord/' + zone + '/' + zone + '/' + nsid)['rdata']
    unless nsentries.include?(rdata['nsdname'])
      # if it shouldn't exist, delete it
      print zone + " has invalid NS record: " + rdata['nsdname']  + ": deleting!\n"
      dyn.delete('NSRecord/' + zone + '/' + zone + '/' + nsid)
    else
      livensentries << rdata['nsdname']
    end
  }

  # confirm/add needed NS records
  nsentries.map { |nsdname|
    unless livensentries.include?(nsdname)
      print zone + " missing NS record: " + nsdname + ": adding\n"
      dyn.post('NSRecord/' + zone + '/' + zone + '/', {"rdata" => { "nsdname" => nsdname} })
    end
  }

  # verify MX/mail
  if attributes.include?('mail')
    if attributes['mail'] == 'google'
      mxentries = { 
        'ASPMX.L.GOOGLE.COM.' => 1,
        'ALT1.ASPMX.L.GOOGLE.COM.' => 5,
        'ALT2.ASPMX.L.GOOGLE.COM.' => 5,
        'ASPMX2.GOOGLEMAIL.COM.' => 10,
        'ASPMX3.GOOGLEMAIL.COM.' => 10}
      cnamerecords['mail.'+zone] = 'ghs.google.com'
      cnamerecords['calendar.'+zone] = 'ghs.google.com'
      cnamerecords['start.'+zone] = 'ghs.google.com'
      cnamerecords['mail.'+zone] = 'ghs.google.com'
    elsif attributes['mail'] == 'ithought'
      mxentries = {'mail.ithought.org.' => 10, 'mail2.ithought.org.' => 20, 'mail3.ithought.org.' => 30}
    else
      print "unknown mail provider: " + attributes['mail'] + "\n"
      exit
    end

    # delete bad MX records
    livemxentries = {}
    dyn.get('MXRecord/' + zone + '/' + zone + '/').map { |mxid|
      mxid.gsub!('/REST/MXRecord/' + zone + '/' + zone + '/', '')
      rdata = dyn.get('MXRecord/' + zone + '/' + zone + '/' + mxid)['rdata']
      unless (mxentries.include?(rdata['exchange']) && mxentries[rdata['exchange']] == rdata['preference'])
        # if it shouldn't exist, delete it
        print zone + " has invalid MX record: " + rdata['exchange'] + ":" + rdata['preference'].to_s  + ": deleting!\n"
        dyn.delete('MXRecord/' + zone + '/' + zone + '/' + mxid)
      else
        livemxentries[rdata['exchange']] = rdata['preference']
      end
    }

    # confirm/add needed mx records
    mxentries.map { |exchange,preference|
      unless (livemxentries.include?(exchange) && livemxentries[exchange] == preference)
        print zone + " missing MX record: " + exchange + ":" + preference.to_s + ": adding\n"
        dyn.post('MXRecord/' + zone + '/' + zone + '/', {"rdata" => { "exchange" => exchange, "preference" => preference } })
      end
    }
  end

  # verify web server pointing
  if attributes.include?('web')
    if attributes['web'] == 'pongo'
      arecords[zone] = '174.34.146.230'
      cnamerecords['www.'+zone] = zone
    else
     print "unknown web provider: " + attributes['web'] + "\n"
     exit
   end
  end

  # make sure all the A records specified above exist and are correct
  # (unlike other record types, this doesn't delete records not specified in the config)
  livearecords = []
  dyn.get('ARecord/' + zone + '/' + zone + '/').map { |aid|
    aid.gsub!('/REST/ARecord/' + zone + '/' + zone + '/', '')
    record = dyn.get('ARecord/' + zone + '/' + zone + '/' + aid)
    # if this record should exist, but points to the wrong IP, fix it
    if arecords.include?(record['fqdn']) && record['rdata']['address'] != arecords[record['fqdn']]
      print zone + " invalid A record: " + record['fqdn'] + ":" + record['rdata']['address'] + ": fixing\n"
      dyn.put('ARecord/' + zone + '/' + zone + '/' + aid, {"rdata" => { "address" => arecords[record['fqdn']] }})
    end
    livearecords << record['fqdn']
  }
  # add A records that should exist but dont
  arecords.map { |fqdn,address|
    unless livearecords.include?(fqdn)
      print zone + " missing A record: " + fqdn + ":" + address + ": adding\n"
      dyn.post('ARecord/' + zone + '/' + fqdn + '/', {"rdata" => { "address" => address}})
    end
  }
 
  # add/correct CNAME records to match config
  cnamerecords.map { |fqdn,cname|
    begin
      dyn.get('CNAMERecord/' + zone + '/' + fqdn + '/').map { |cnameid|
        cnameid.gsub!('/REST/CNAMERecord/' + zone + '/' + fqdn + '/', '')
        record = dyn.get('CNAMERecord/' + zone + '/' + fqdn + '/' + cnameid)
        if record['rdata']['cname'] != cname + '.'
          print zone + " invalid CNAME record: " + record['fqdn'] + ":" + record['rdata']['cname'] + ": fixing\n"
          dyn.put('CNAMERecord/' + zone + '/' + fqdn + '/' + cnameid + '/' , 
                  {"rdata" => { "cname" => cnamerecords[record['fqdn']] }})
        end
      }
    rescue DynectRest::Exceptions::RequestFailed => e
      print zone + " missing CNAME record: " + fqdn + ":" + cname + ": adding\n"
      dyn.post('CNAMERecord/' + zone + '/' + fqdn + '/', {"rdata" => { "cname" => cname}})
    end
  }

  #publish all changes
  dyn.publish(zone)
}
