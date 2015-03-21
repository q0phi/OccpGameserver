#$LOAD_PATH.unshift("#{File.dirname(__FILE__)}/../lib")
require "minitest/autorun"
require "minitest/unit"
require "minitest/benchmark"

require "socket"
require "log4r"
require_relative "../lib/OCCPGameServer/iptools"
require_relative "../lib/OCCPGameServer/errors"

class IPToolsTest < Minitest::Test

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
       # fileoutputter = Log4r::FileOutputter.new('GameServer', {:trunc => true , :filename => 'testlog.log'})
       # fileoutputter.formatter = Log4r::PatternFormatter.new({:pattern => "[%l] %d %x %m", :date_pattern => "%m-%d %H:%M:%S"})
       # $log.outputters = [fileoutputter]
 
        #$log = Logger.new(STDOUT)
        #$log.level = Logger::DEBUG

    end

    ##
    # Test create a single name space and ensure it has the correct ip address in it
    #
    def test_ns_create

        netAddr = {}
        netAddr[:iface] = 'eth1'
        netAddr[:ipaddr] = '1.2.3.6' #@listips[Random.rand(7)]
        netAddr[:cidr] = '24'
        netAddr[:gateway] = nil

        begin
            field1 = OCCPGameServer::IPTools.ns_create("OCCPnsTest", netAddr)
        rescue ArgumentError => e
            print e.message
        end

        pR, pW = IO.pipe
        
        command = "ip addr | grep 'inet'| grep 'eth0' | cut -d'/' -f1 | awk '{ print $2}'"
        pid = spawn( field1.comwrap(command), :out=>pW, :err=>"/dev/null")
        pW.close
        Process.wait pid
        addrAssignCheck = $?.exitstatus

        system(field1.comwrap('nping -c 1 1.2.3.4'), [:out, :err]=>"/dev/null")
        pingret = $?.exitstatus

        collectedAddress = pR.read.delete!("\n")
        pR.close
        nsDeleted = field1.delete
        
        assert_equal 0, pingret
        assert_equal true, nsDeleted
        assert_equal 0, addrAssignCheck
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
end
class IPToolsBench < Minitest::Benchmark
    
    class NetDef
        attr_accessor :netAddr
        def initialize()
            @listips = [ '10.24.32.123',
                        '10.24.32.24',
                        '10.24.32.125',
                        '10.24.32.126',
                        '10.24.32.77',
                        '10.24.32.228',
                        '10.24.32.129']

            netAddr = {}
            netAddr[:iface] = 'eth1'
            netAddr[:ipaddr] = '1.2.3.6' #@listips[Random.rand(7)]
            netAddr[:cidr] = '24'
            netAddr[:gateway] = nil
            @netAddr = netAddr
            @seri = 0
        end
        def rerun(n)
            n.times do |count|
                OCCPGameServer::IPTools.ns_create("OCCP#{@seri}ns#{count}", @netAddr)
            end
                @seri += 1
        end
    end

    def self.bench_range
        return Minitest::Benchmark.bench_exp(1,100)
    end
   
    def initialize( somevar )
        super
        @netObj = NetDef.new
        
        $log = Log4r::Logger.new('occp::gameserver::testlog')
        fileoutputter = Log4r::FileOutputter.new('GameServer', {:trunc => true , :filename => "#{File.dirname(__FILE__)}/testlog_benchmarks.log"})
        fileoutputter.formatter = Log4r::PatternFormatter.new({:pattern => "[%l] %d %x %m", :date_pattern => "%m-%d %H:%M:%S"})
        $log.outputters = [fileoutputter]
 
        #$log = Logger.new(STDOUT)
        #$log.level = Logger::DEBUG

    end


    def bench_creation_speed
        assert_performance_linear 0.99 do |n|
            @netObj.rerun(n)
        end
        `ip netns list | grep -E 'OCCP' | xargs -L 1 ip netns delete`
    end

end
