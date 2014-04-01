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

                pid = spawn("ip link add link #{@rootIF} dev if#{@nsName} type macvlan mode bridge")
                #print("add link\n")
                Process.wait pid
                pid = spawn("ip netns add #{@nsName}")
                #print("create ns\n")
                Process.wait pid
                pid = spawn("ip link set if#{@nsName} netns #{@nsName}")
                #print("move link to ns\n")
                Process.wait pid
                pid = spawn("ip netns exec #{@nsName} ip link set if#{@nsName} name eth0")
                #print("change link name\n")
                Process.wait pid
                pid = spawn("ip netns exec #{@nsName} ip addr add #{@ipaddr} dev eth0")
                #print("add address\n")
                Process.wait pid
                #pid = spawn("ip netns exec #{@nsName} ip route delete default")
                #print("rem default route\n")
                pid = spawn("ip netns exec #{@nsName} ip link set eth0 up")
                #print("set link up\n")
                Process.wait pid
            end
            #run command
            def run(command)
                ret = system("ip netns exec #{@nsName}  #{command}", :out=>'/dev/null')
            end

            #destroy the namespace
            def delete
               system("ip netns del #{@nsName}") 
            end
        end

        #create a named network namespace
        def self.ns_create(nsName,rootIF, ipaddr)

            #check if the name or ip has been issued
            raise ArgumentError if system("ip netns list | grep -i #{nsName}") == 0

            iStruct = NetNS.new(nsName, rootIF, ipaddr)

            return iStruct
        end


        #create a namespace address pool
        def ns_pool_create(name, number)

        end

        #destroy a namespace pool
        def ns_pool_destroy(name)

        end



    end
end
