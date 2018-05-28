#!/bin/bash
# generate default iptables rules
# mangle
iptables --table mangle --flush

iptables --table mangle --append PREROUTING --match conntrack --ctstate INVALID --match comment --comment "Block Invalid Packets" --jump DROP

iptables --table mangle --append PREROUTING --protocol tcp ! --syn --match conntrack --ctstate NEW --match comment --comment "Block New Packets That Are Not SYN" --jump DROP

iptables --table mangle --append PREROUTING --protocol tcp --match conntrack --ctstate NEW --match tcpmss ! --mss 536:65535 --match comment --comment "Block Uncommon MSS Values" --jump DROP

iptables --table mangle --append PREROUTING --protocol tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE --match comment --comment "Block Packets With Bogus TCP Flags" --jump DROP
iptables --table mangle --append PREROUTING --protocol tcp --tcp-flags FIN,SYN FIN,SYN --match comment --comment "Block Packets With Bogus TCP Flags" --jump DROP
iptables --table mangle --append PREROUTING --protocol tcp --tcp-flags SYN,RST SYN,RST --match comment --comment "Block Packets With Bogus TCP Flags" --jump DROP
iptables --table mangle --append PREROUTING --protocol tcp --tcp-flags FIN,RST FIN,RST --match comment --comment "Block Packets With Bogus TCP Flags" --jump DROP
iptables --table mangle --append PREROUTING --protocol tcp --tcp-flags FIN,ACK FIN --match comment --comment "Block Packets With Bogus TCP Flags" --jump DROP
iptables --table mangle --append PREROUTING --protocol tcp --tcp-flags ACK,URG URG --match comment --comment "Block Packets With Bogus TCP Flags" --jump DROP
iptables --table mangle --append PREROUTING --protocol tcp --tcp-flags ACK,FIN FIN --match comment --comment "Block Packets With Bogus TCP Flags" --jump DROP
iptables --table mangle --append PREROUTING --protocol tcp --tcp-flags ACK,PSH PSH --match comment --comment "Block Packets With Bogus TCP Flags" --jump DROP
iptables --table mangle --append PREROUTING --protocol tcp --tcp-flags ALL ALL --match comment --comment "Block Packets With Bogus TCP Flags" --jump DROP
iptables --table mangle --append PREROUTING --protocol tcp --tcp-flags ALL NONE --match comment --comment "Block Packets With Bogus TCP Flags" --jump DROP
iptables --table mangle --append PREROUTING --protocol tcp --tcp-flags ALL FIN,PSH,URG --match comment --comment "Block Packets With Bogus TCP Flags" --jump DROP
iptables --table mangle --append PREROUTING --protocol tcp --tcp-flags ALL SYN,FIN,PSH,URG --match comment --comment "Block Packets With Bogus TCP Flags" --jump DROP
iptables --table mangle --append PREROUTING --protocol tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG --match comment --comment "Block Packets With Bogus TCP Flags" --jump DROP

iptables --table mangle --append PREROUTING --fragment --match comment --comment "Blocks fragmented packets" --jump DROP

# filter
iptables --table filter --flush
iptables --table filter --delete-chain LOGGING

iptables --table filter --new LOGGING
iptables --table filter --append LOGGING --match limit --limit 100/s --limit-burst 20 --match comment --comment "logging dropped packets" --jump LOG --log-prefix "Filter-Dropped: " --log-level warning
iptables --table filter --append LOGGING --jump DROP

iptables --table filter --append INPUT --protocol tcp --tcp-flags RST RST --match limit --limit 2/s --limit-burst 2 --match comment --comment "Allow incoming TCP RST packets" --jump ACCEPT
iptables --table filter --append INPUT --protocol tcp --tcp-flags RST RST --match comment --comment "Limit incoming TCP RST packets to mitigate TCP RST floods" --jump LOGGING

iptables --table filter --append INPUT --protocol tcp --tcp-flags SYN,ACK,FIN,RST RST --match limit --limit 2/s --limit-burst 2 --match comment --comment "Protection against port scanning" --jump ACCEPT
iptables --table filter --append INPUT --protocol tcp --tcp-flags SYN,ACK,FIN,RST RST --match comment --comment "Protection against port scanning" --jump LOGGING

iptables --table filter --append INPUT --match conntrack --ctstate ESTABLISHED,RELATED --match comment --comment "Allow related connections" --jump ACCEPT

iptables --table filter --append INPUT --protocol tcp --match connlimit --connlimit-above 64 --match comment --comment "Rejects connections from hosts that have more than 64 established connections" --jump REJECT --reject-with tcp-reset

iptables --table filter --append INPUT --protocol tcp --dport ssh --match conntrack --ctstate NEW --match recent --set --match comment --comment "record ssh connection"
iptables --table filter --append INPUT --protocol tcp --dport ssh --match conntrack --ctstate NEW --match recent --update --seconds 60 --hitcount 5 --match comment --comment "SSH brute-force protection" --jump LOGGING

iptables --table filter --append INPUT --protocol tcp --match conntrack --ctstate NEW --match limit --limit 32/s --limit-burst 20 --match comment --comment "Allow the new TCP connections that a client can establish per second under limit" --jump ACCEPT
iptables --table filter --append INPUT --protocol tcp --match conntrack --ctstate NEW --match comment --comment "Limits the new TCP connections that a client can establish per second" --jump LOGGING

iptables --table filter --append INPUT --jump LOGGING
