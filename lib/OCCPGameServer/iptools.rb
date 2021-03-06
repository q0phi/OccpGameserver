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
            end

            def get_registered_netns(netAddr)

                # NetNS Name
                netNSName = "occp_#{netAddr[:ipaddr].gsub(".","_")}_#{netAddr[:iface]}"
                
                nsHandle = nil
                ## ENTER CRITICAL
                @regMutex.synchronize do
                    # Check if the NS Exists
                    if @registry.member?(netNSName)
                        
                        $log.debug 'Found IP namespace in registry'
                        
                        # increment the ref count
                        @registry[netNSName][:refcount] += 1
                        @registry[netNSName][:lastuse] = Time.now.to_f
                    
                        nsHandle = @registry[netNSName][:handle]
                        
                        # remove this item from the shortlist if it exists there        
                        @shortList.delete(netNSName) 
                    else
                        $log.debug 'IP namespace not found in registry'

                        # create the ns if it does not exist
                        # I don't know if this check is neccesary, when we try to add the name space it will just fail later
                        # raise NamespaceError, 'namespace name already exists' if system("ip netns list | grep -E '^#{nsName}$'", [:out, :err]=>"/dev/null") == true
                        #
                        # We may catcha NamespaceError thrown in the following function,
                        # we could then try and re-sync the registry to the existing namespaces.
                        # For now let the error fail up, and the Event Handler can choose what to do.
                        nsHandle = NetNS.new(netNSName, netAddr) #IPTools.ns_create(netNSName, netAddr)

                        @registry[netNSName] = {:handle => nsHandle, :refcount => 1, :lastuse => Time.now.to_f}

                    end
                   
                    ## Visual debugging of network namespaces
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
                        
                        if refCount <= 0
                            #The item should remain for at least NETNS_LIFTIME after last use
                            @registry[netNSName][:lastuse] = Time.now.to_f
                            @registry[netNSName][:refcount] = 0
                            @shortList << netNSName
                        else
                            @registry[netNSName][:refcount] = refCount
                        end
                    end

                    #cleanup the shortlist so it will eventually release unused namespaces
                    @shortList.each do |netNS|
                        if Time.now.to_f - @registry[netNS][:lastuse] > NETNS_LIFETIME #seconds to live for an unsued namespace
                            #release the NS
                            
                            #confirm that the system has actually removed the namespace.
                            ret = @registry[netNS][:handle].delete
                            if ret
                                @registry.delete(netNS)
                                @shortList.delete(netNS)
                            end

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
            @@serial = 1
            
            def initialize(nsName, netAddr)
                Log4r::NDC.set_max_depth(72)
                Log4r::NDC.push('NetNS:')
                
                @nsName = nsName
                
                @ipaddr = netAddr[:ipaddr]
                @ipDomain = [@ipaddr,netAddr[:cidr]].join('/')
                @rootIF = netAddr[:iface]

                #Just dump the traffic on the interface if no gateway specified
                if netAddr[:gateway].nil? || netAddr[:gateway].empty?
                    gateway = # " ip route delete default ||
                                " ip route add default via #{@ipaddr}\""
                else
                    gateway = # " ip route delete default ||
                               " ip route add #{netAddr[:gateway]} dev eth0 &&
                                 ip route add default via #{netAddr[:gateway]}\""
                end

                #TODO Move this some place beeeter out of the event launch path
                #Set the master interface into promisc mode so we can receive replies for the fake-interface
               # pid = spawn("ip link set #{@rootIF} promisc on", [:out,:err]=>"/dev/null")
               # Process.wait pid
               # raise NamespaceError, "failed to set link #{@rootIF} to promisc mode" if $?.exitstatus != 0
                
                # This helps not repeating the temp interface names
                @@serial += 1
                tempIFace = 'xif' + @@serial.to_s 
                #
                # Try to speed set the interface
                #
                cache ="ip link add link #{@rootIF} dev #{tempIFace} type macvlan mode private &&
                        ip netns add #{@nsName} &&
                        ip link set #{tempIFace} netns #{@nsName} &&
                        ip netns exec #{@nsName} /bin/sh -c \"ip link set #{tempIFace} name eth0 && 
                                                                ip addr add #{@ipDomain} dev eth0 &&
                                                                ip link set lo up &&
                                                                ip link set eth0 up &&" + gateway

                cache.delete!("\n")
                pid = spawn(cache , [:out,:err]=>"/dev/null")

                Process.wait pid
                if $?.exitstatus == 0
                    $log.info "Speed Set Successful"
                    Log4r::NDC.pop
                    return
                else
                    $log.debug "Failed speed set of namespace #{@nsName} trying slow setup"
                    # This cleanup might be too agressive
                    npid = []
                    npid << spawn("ip link delete #{tempIFace}", [:out,:err]=>"/dev/null")
                    npid << spawn("ip netns delete #{@nsName}", [:out,:err]=>"/dev/null")
                    npid.each {|ipid|
                        Process.wait ipid
                    }
                end
                #
                # Begin slow method of setup if needed
                #
                $log.debug "Creating temporary link to interface #{rootIF}"
                retCode = system("ip link add link #{@rootIF} dev #{tempIFace} type macvlan mode private", [:out,:err]=>"/dev/null")
                raise NamespaceError, "failed to create initial link #{tempIFace}" if !retCode

                $log.debug "Creating namespace"
                retCode = system("ip netns add #{@nsName}", [:out,:err]=>"/dev/null")
                if !retCode
                    #Clean the link created
                    system("ip link delete #{tempIFace}", [:out,:err]=>"/dev/null")
                    raise NamespaceError, "failed to create namespace named: #{@nsName}"
                end

                $log.debug "Moving link into namespace"
                retCode = system("ip link set #{tempIFace} netns #{@nsName}", [:out,:err]=>"/dev/null")
                if !retCode
                    #Clean the link created
                    system("ip link delete #{tempIFace}", [:out,:err]=>"/dev/null")
                    #Clean the namespace created
                    system("ip netns delete #{@nsName}", [:out,:err]=>"/dev/null")
                    raise NamespaceError, "failed to move interface #{tempIFace} into namespace #{@nsName} "
                end
            
                $log.debug "Changing local link name"
                retCode = system("ip netns exec #{@nsName} ip link set #{tempIFace} name eth0", [:out,:err]=>"/dev/null")
                if !retCode
                    #Clean the namespace created; this auto-deletes the link created earlier
                    system("ip netns delete #{@nsName}", [:out,:err]=>"/dev/null")
                    raise NamespaceError, "failed to change local link name"
                end

                $log.debug "Adding address to local link in namespace"
                retCode = system("ip netns exec #{@nsName} ip addr add #{@ipDomain} dev eth0", [:out,:err]=>"/dev/null") #print("add address\n")
                if !retCode
                    #Clean the namespace created
                    system("ip netns delete #{@nsName}", [:out,:err]=>"/dev/null")
                    raise NamespaceError, "failed to add address #{@ipaddr} to iface"
                end

                $log.debug "Setting interfaces UP"
                retCode1 = system("ip netns exec #{@nsName} ip link set lo up", [:out,:err]=>"/dev/null") #print("set link up\n")
                retCode2 = system("ip netns exec #{@nsName} ip link set eth0 up", [:out,:err]=>"/dev/null") #print("set link up\n")
                if !retCode1 and !retCode2
                    #Clean the namespace created
                    system("ip netns delete #{@nsName}", [:out,:err]=>"/dev/null")
                    raise NamespaceError, "failed to set link active"
                end
               # There should not be a default route in a new namespace 
               #pid = spawn("ip netns exec #{@nsName} ip route delete default", [:out,:err]=>"/dev/null") #print("rem default route\n")
               #Process.wait pid
                # Optionally add a default gateway
                if netAddr[:gateway].nil? || netAddr[:gateway].empty?
                    $log.debug "Adding default gateway via own ip address"
                    retCode = system("ip netns exec #{@nsName} ip route add default via #{@ipaddr}") #print("add default route\n")
                    if !retCode
                        #Clean the namespace created
                        system("ip netns delete #{@nsName}", [:out,:err]=>"/dev/null")
                        raise NamespaceError, "failed to set default gateway"
                    end
                else
                    $log.debug "Adding default gateway via #{netAddr[:gateway]}"
                    # The gateway must be on this link, but might be in a different subnet
                    retCode = system("ip netns exec #{@nsName} ip route add #{netAddr[:gateway]} dev eth0") #print("add default route\n")
                    if !retCode
                        #Clean the namespace created
                        system("ip netns delete #{@nsName}", [:out,:err]=>"/dev/null")
                        raise NamespaceError, "failed to set gateway as link local"
                    end
                    
                    retCode = system("ip netns exec #{@nsName} ip route add default via #{netAddr[:gateway]}") #print("add default route\n")
                    if !retCode
                        #Clean the namespace created
                        system("ip netns delete #{@nsName}", [:out,:err]=>"/dev/null")
                        raise NamespaceError, "failed to set default gateway"
                    end
                
                end
                Log4r::NDC.pop
            end #END NetNS initialize
            
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

            ##
            # Run a shell command directly
            #
            def run(command)
                pid = spawn("ip netns exec #{@nsName}  #{command}", [:out,:err]=>"/dev/null")
                Process.wait pid
                $?.exitstatus
            end
            
            ##
            # Destroy the namespace
            #
            def delete
               system("ip netns del #{@nsName}", [:out,:err]=>"/dev/null") 
            end
        end

        ##
        # Create a network namespace for the provided interface and IPv4 address
        # TODO Remove this function
        def self.ns_create(nsName, netAddr)
            $log.debug "Creating namespace for #{nsName}"
            #check if the name or ip has been issued
            #raise NamespaceError, 'namespace name already exists' if system("ip netns list | grep -E '^#{nsName}$'", [:out, :err]=>"/dev/null") == true
            NetNS.new(nsName, netAddr)
        end


        ##
        # Generate an array of subnet addresses
        # Possibly Deprecated?
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
        
        ##
        # Create a list of addresses from a block definition
        #
        def self.generate_address_list(addrDef)
            
            list = Array.new
            
            #calculate the address space size
            addr = addrDef[:addr]
            #ipaddr,netmask = addr.split('/')
            aSpace = NetAddr::CIDR.create(addr)

            sizeOf = aSpace.size
            count = 0
            raise ArgumentError,"CIDR ip pool size is smaller than requested count of addresses" if addrDef[:count].to_i > sizeOf
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
