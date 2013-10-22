require 'rubygems'
require 'dynect_rest'

#config.rb contains values for ACCOUNT, USER, PASS, and SOACONTACT
require 'config.rb'

require 'domains.rb'

dyn = DynectRest.new(ACCOUNT, USER, PASS)
dyn.get('Zone').map { |zone| 
  zone.gsub!("/REST/Zone",'').gsub!('/','')	
  dyn.get('SOARecord/' + zone + '/' + zone + '/').map { |soaid| 
    soaid.gsub!('/REST/SOARecord/' + zone + '/' + zone + '/', '')
    rdata = dyn.get('SOARecord/' + zone + '/' + zone + '/' + soaid)['rdata']
    puts rdata
    if rdata['rname']  != SOACONTACT + '.'
      print zone + " has invalid SOA Contact: " + rdata['rname'] + ": fixing!\n"
      dyn.put('SOARecord/' + zone + '/' + zone + '/' + soaid, {"rdata" => { "rname" => SOACONTACT } })
      dyn.publish(zone)
    end
  }
}
