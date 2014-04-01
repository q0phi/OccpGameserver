#$LOAD_PATH.unshift("#{File.dirname(__FILE__)}/../lib")
require "test/unit"
require_relative "../lib/OCCPGameServer/iprand"
require "socket"

class IPRandTest < Test::Unit::TestCase

    def initialize( somevar )
        super
        @listips = [ '10.24.32.123/24',
                    '10.24.32.24/24',
                    '10.24.32.125/24',
                    '10.24.32.126/24',
                    '10.24.32.77/24',
                    '10.24.32.228/24',
                    '10.24.32.129/24']

        #This directory is required to exist
        system('mkdir -p /var/run/netns')
    end

    def test_ns_create

        ifName = 'eth0'
        ipAddr = @listips[Random.rand(7)]

        field1 = OCCPGameServer::IPRand.ns_create("OCCPnsTest", ifName, ipAddr)

        pR, pW = IO.pipe
        
        command = "ip addr | grep 'inet'| grep '#{ifName}' | cut -d'/' -f1 | awk '{ print $2}'"
        pid = spawn( field1.comwrap(command), :out=>pW, :err=>"/dev/null")
        
        pW.close
        Process.wait pid
       
        collectedAddress = pR.read.delete!("\n")
        pR.close
        field1.delete
        
        assert_equal 0, $?.exitstatus
        assert_equal ipAddr.split('/')[0], collectedAddress

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
