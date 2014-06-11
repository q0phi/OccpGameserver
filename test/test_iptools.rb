#$LOAD_PATH.unshift("#{File.dirname(__FILE__)}/../lib")
require "test/unit"
require_relative "../lib/OCCPGameServer/iptools"
require "socket"
require "log4r"

class IPToolsTest < Test::Unit::TestCase

    def initialize( somevar )
        super
        @listips = [ '10.24.32.123',
                    '10.24.32.24',
                    '10.24.32.125',
                    '10.24.32.126',
                    '10.24.32.77',
                    '10.24.32.228',
                    '10.24.32.129']

        #This directory is required to exist
        system('mkdir -p /var/run/netns')
        $log = Log4r::Logger.new('occp::gameserver::testlog')
        
        #$log = Logger.new(STDOUT)
        #$log.level = Logger::DEBUG

    end

    def test_ns_create

        netAddr = {}
        netAddr[:iface] = 'eth0'
        netAddr[:ipaddr] = @listips[Random.rand(7)]
        netAddr[:cidr] = '24'
        netAddr[:gateway] = nil

        begin
            field1 = OCCPGameServer::IPTools.ns_create("OCCPnsTest", netAddr)
        rescue ArgumentError => e
            print e.message
        end

        pR, pW = IO.pipe
        
        command = "ip addr | grep 'inet'| grep '#{netAddr[:iface]}' | cut -d'/' -f1 | awk '{ print $2}'"
        pid = spawn( field1.comwrap(command), :out=>pW, :err=>"/dev/null")
        
        pW.close
        Process.wait pid
       
        collectedAddress = pR.read.delete!("\n")
        pR.close
        nsDeleted = field1.delete
        

        assert_equal true, nsDeleted
        assert_equal 0, $?.exitstatus
        assert_equal netAddr[:ipaddr], collectedAddress

    end
    
    ##
    #Test generate ip address block
    #
    def test_gen_ip
        
        number = 23
        
        block = OCCPGameServer::IPTools.gen_ip_block(number)

        block.each do |e|
            assert( ( e > 0 && e < 255 ) , "ip subnet adress out of range" )
        end

        assert_equal( block.length, number, "number of addresses not sufficient")

    end


#    def test_speed
#
#        total = 0
#        100.times do |count|
#
#            field1 = OCCPGameServer::IPRand.ns_create("OCCPns#{count}", 'eth1',  listips[Random.rand(7)])
#            ret = field1.run('ifconfig eth0')
#            field1.delete
#
#        end
#    
#    end
end
