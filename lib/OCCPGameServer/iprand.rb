module OCCPGameServer
    class IPRand

        #return a new Struct for the NS
        class NetNS 
            attr_accessor :rootIF, :nsName, :ipaddr
            #:nsName = nsName
            #:ipaddr = ipaddr
            def initialize(nsName, rootIF, ipaddr)
                @nsName = nsName
                @ipaddr = ipaddr
                @rootIF = rootIF

                pid = spawn("ip link add link #{@rootIF} dev if#{@nsName} type macvlan mode bridge", [:out,:err]=>"/dev/null")
                #print("add link\n")
                Process.wait pid
                pid = spawn("ip netns add #{@nsName}", [:out,:err]=>"/dev/null")
                #print("create ns\n")
                Process.wait pid
                pid = spawn("ip link set if#{@nsName} netns #{@nsName}", [:out,:err]=>"/dev/null")
                #print("move link to ns\n")
                Process.wait pid
                pid = spawn("ip netns exec #{@nsName} ip link set if#{@nsName} name eth0", [:out,:err]=>"/dev/null")
                #print("change link name\n")
                Process.wait pid
                pid = spawn("ip netns exec #{@nsName} ip addr add #{@ipaddr} dev eth0", [:out,:err]=>"/dev/null")
                #print("add address\n")
                Process.wait pid
                #pid = spawn("ip netns exec #{@nsName} ip route delete default")
                #print("rem default route\n")
                pid = spawn("ip netns exec #{@nsName} ip link set eth0 up", [:out,:err]=>"/dev/null")
                #print("set link up\n")
                Process.wait pid
            end
            
            ##
            # Wrap a command with a namespace context
            #
            def comwrap(command)
                if command.kind_of?(Array)
                    comprefix = ['ip netns exec #{nsName}']
                    corecommand = comprefix.concat(command)
                else
                    corecommand = "ip netns exec #{nsName} #{command}"
                end
                return corecommand
            end


            #run command
            def run(command)
                pid = spawn("ip netns exec #{@nsName}  #{command}", [:out,:err]=>"/dev/null")
                Process.wait pid
                $?.exitstatus
            end

            #destroy the namespace
            def delete
               system("ip netns del #{@nsName}") 
            end
        end

        ##
        # Create a network namespace for the provided interface and IPv4 address
        #
        def self.ns_create(nsName, interface, ipAddr)

            #check if the name or ip has been issued
            raise ArgumentError if system("ip netns list | grep -i #{nsName}") == 0
            NetNS.new(nsName, interface, ipAddr)
        end


        #create a namespace address pool
        def ns_pool_create(name, number)

        end

        #destroy a namespace pool
        def ns_pool_destroy(name)

        end

        ##
        # Generate an array of subnet addresses
        #
        def self.gen_ip_block(number)

            #generate one extra address for ranging
            #number += 1

            require 'set'
            require 'simple-random'

            sr = SimpleRandom.new
            sr.set_seed()
            
            ips = Set.new

            while ips.length <= number
                ips << sr.chi_square(2)
            end

            #normalize
            max_value = ips.to_a.max

            ipsa = ips.to_a.map{|e| ((e / max_value) * 254 ).to_i }
            #print "#{ipsa.length} -- #{ipsa.sort!.to_s}\n\n"

            #De-dup
            ipsa.sort!.reverse!.shift
            ips = Set.new
            ipsa.each{|e|
                while ips.member?(e) do
                    e -= 1
                end
                #if e <= 0 # we reached the bottom search upwards
                    while (e <= 0 || ips.member?(e)) && e < 254 do
                        e += 1
                    end
                #end
                ips << e
            }
            ips.to_a
        end
        



    end
end
