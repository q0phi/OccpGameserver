module OCCPGameServer
    class IPTools

        ##
        # A thread-safe network namespace registry class
        #
        class NetNSRegistry

            def initialize()
                @registry = {}
                @regMutex = Mutex.new
                # Protect namespaces from being thrashed
                @shortList = Array.new
                @lifetime = GameServerConfig::NETNS_LIFETIME #seconds
            end

            def get_registered_netns(netAddr)

                # NetNS Name
                netNSName = "occp_#{netAddr[:ipaddr].gsub(".","_")}_#{netAddr[:iface]}"
                
                nsHandle = nil
                ## ENTER CRITICAL
                @regMutex.synchronize do
                    # Check if the NS Exists
                    if @registry.member?(netNSName)

                        # increment the ref count
                        @registry[netNSName][:refcount] += 1
                        @registry[netNSName][:lastuse] = Time.now.to_f
                    
                        nsHandle = @registry[netNSName][:handle]
                        
                        # remove this item from the shortlist if it exists there        
                        @shortList.delete(netNSName) 
                    else
                        # create the ns
                        nsHandle = IPTools.ns_create(netNSName, netAddr)

                        @registry[netNSName] = {:handle => nsHandle, :refcount => 1, :lastuse => Time.now.to_f}

                    end
                   #Visual debugging of network namespaces
                   # system("clear")
                   #     print "refcount ::  lastuse  \t::  netns\n"
                   # @registry.each do |(k,mem)|
                   #     print "    #{mem[:refcount]}    ::   #{(Time.now.to_f - mem[:lastuse]).to_i} \t:: #{k} \n"
                   # end
                end
                ## EXIT CRITICAL

                return nsHandle
            end

            def release_registered_netns(netNSName)

                ## ENTER CRITICAL
                @regMutex.synchronize do
                    # Check if the NS Exists
                    if @registry.member?(netNSName)

                        # decrement the ref count
                        refCount = @registry[netNSName][:refcount] - 1
                        #refCount -= 1
                        
                        if refCount <= 0
                            #The item should remain for at least @liftime after last use
                            @registry[netNSName][:lastuse] = Time.now.to_f
                            @registry[netNSName][:refcount] = 0
                            @shortList << netNSName
                        else
                            @registry[netNSName][:refcount] = refCount
                        end
                    end

                    #cleanup the shortlist so it will eventually release unused namespaces
                    @shortList.each do |netNS|
                        if Time.now.to_f - @registry[netNS][:lastuse] > @lifetime
                            #release the NS
                            netns = @registry.delete(netNS)
                            @shortList.delete(netNS)
                            netns[:handle].delete
                        end
                    end
                end
                ## EXIT CRITICAL
            end

        end # End NetNSRegistry Class
        
        ##
        # A representation of a network namespace execution context
        #
        class NetNS 
            attr_reader :rootIF, :nsName, :ipaddr
            #:nsName = nsName
            #:ipaddr = ipaddr
            def initialize(nsName, netAddr)
                @nsName = nsName
                
                @ipaddr = netAddr[:ipaddr]
                @ipDomain = [@ipaddr,netAddr[:cidr]].join('/')
                @gateway = netAddr[:gateway]
                @rootIF = netAddr[:iface]

                #print netAddr.to_s.red

                tempIFace = "if#{rand(256)}"
                
                begin
                    pid = spawn("ip link add link #{@rootIF} dev #{tempIFace} type macvlan mode bridge", [:out,:err]=>"/dev/null") #print("add link\n")
                    Process.wait pid
                    raise ArgumentError, "failed to create initial link" if $?.exitstatus != 0

                    pid = spawn("ip netns add #{@nsName}", [:out,:err]=>"/dev/null") #print("create ns\n")
                    Process.wait pid
                    raise ArgumentError, "failed to create namespace named: #{@nsName}" if $?.exitstatus != 0

                    pid = spawn("ip link set #{tempIFace} netns #{@nsName}", [:out,:err]=>"/dev/null") #print("move link to ns\n")
                    Process.wait pid
                    raise ArgumentError, "failed to move interface #{tempIFace} into namespace #{@nsName} " if $?.exitstatus != 0
                
                    pid = spawn("ip netns exec #{@nsName} ip link set #{tempIFace} name eth0", [:out,:err]=>"/dev/null") #print("change link name\n")
                    Process.wait pid
                    raise ArgumentError, "failed to change local link name" if $?.exitstatus != 0

                    pid = spawn("ip netns exec #{@nsName} ip addr add #{@ipDomain} dev eth0", [:out,:err]=>"/dev/null") #print("add address\n")
                    Process.wait pid
                    raise ArgumentError, "failed to add address #{@ipaddr} to iface" if $?.exitstatus != 0

                    pid = spawn("ip netns exec #{@nsName} ip link set lo up", [:out,:err]=>"/dev/null") #print("set link up\n")
                    Process.wait pid
                    pid = spawn("ip netns exec #{@nsName} ip link set eth0 up", [:out,:err]=>"/dev/null") #print("set link up\n")
                    Process.wait pid
                    raise ArgumentError, "failed to set link active" if $?.exitstatus != 0
                    
                    pid = spawn("ip netns exec #{@nsName} ip route delete default", [:out,:err]=>"/dev/null") #print("rem default route\n")
                    Process.wait pid
                    # Optionally add a default gateway
                    if @gateway.nil? || @gateway.empty?
                        pid = spawn("ip netns exec #{@nsName} ip route add default via #{@ipaddr}") #print("add default route\n")
                        Process.wait pid
                        raise ArgumentError, "failed to set default gateway" if $?.exitstatus != 0
                    else
                        pid = spawn("ip netns exec #{@nsName} ip route add default via #{@gateway}") #print("add default route\n")
                        Process.wait pid
                        raise ArgumentError, "failed to set default gateway" if $?.exitstatus != 0
                    
                    end

                rescue ArgumentError => e
                    #cleanup namespace
                    system("ip link del #{tempIFace}")
                    system("ip netns list | awk '{print $0;}'| xargs -L 1 ip netns delete")
                    print e.message.red
                    exit(1)
                end
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
               system("ip netns del #{@nsName}", [:out,:err]=>"/dev/null") 
            end
        end

        ##
        # Create a network namespace for the provided interface and IPv4 address
        #
        def self.ns_create(nsName, netAddr)

            #check if the name or ip has been issued
            raise ArgumentError if system("ip netns list | grep -i #{nsName}") == 0
            NetNS.new(nsName, netAddr)
        end


        ##
        # Generate an array of subnet addresses
        #
        def self.gen_ip_block(number)

            #generate one extra address for ranging
            #number += 1

            require 'set'
            #require 'simple-random'

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
        
        ##
        # Create a list of addresses from a block definition
        #
        def self.generate_address_list(addrDef)
            
            list = Array.new
            
            #calculate the address space size
            addr = addrDef[:addr]
            ipaddr,netmask = addr.split('/')
            aSpace = NetAddr::CIDR.create(addr)

            sizeOf = aSpace.size
            count = 0
            while count < addrDef[:count].to_i && list.length < sizeOf - 2 do

                newAddr = aSpace.nth(rand(sizeOf))
                lastoctet = newAddr.split('.')[3]
                if list.include?(newAddr) || lastoctet == "0" || lastoctet == "255"
                    next
                else
                    count += 1
                    list << newAddr
                end

            end

            return list
        end


    end
end
