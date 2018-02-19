#$LOAD_PATH.unshift("#{File.dirname(__FILE__)}/../lib")
require "minitest/autorun"
require "minitest/unit"
require "minitest/benchmark"

require "socket"
require "log4r"
require "colorize"
require_relative "../lib/OCCPGameServer/utils"
require_relative "../lib/OCCPGameServer/team"
require_relative "../lib/OCCPGameServer/errors"
require_relative "../lib/OCCPGameServer/gmessage"
require_relative "../lib/OCCPGameServer/Events/event"
require_relative "./classes/testevent"
require_relative "../lib/OCCPGameServer/Handlers/handler"
require_relative "./classes/testhandler"

$tmpDir = "#{File.dirname(__FILE__)}/tmp"
system('mkdir -p '+$tmpDir, [:out, :err]=>'/dev/null')

class TeamTest < Minitest::Test

    class FakeCore
        attr_accessor :handler, :gameclock, :INBOX

        def initialize
            @gameclock = FakeClock.new
            @INBOX = Queue.new
        end
        def get_handler(eventHandler)
            return @handler
        end
        def get_ip_pool(ipAddress)
            return {:ifname => 'eth0',:addresses=>['10.10.10.10'],:cidr=>'32',:gateway=>'10.10.10.10'}
        end
        def get_netns(ipaddress)
        end 
    end
    class FakeClock
        def initialize
            @gamestart = 0.0
        end
        def gametime
            return Time.now.to_f - @gamestart
        end
        def start
            @gamestart = Time.now.to_f
        end
    end
    def initialize( somevar )
        super

        #This directory is required to exist
        $log = Log4r::Logger.new('occp::gameserver::testlog')
        fileoutputter = Log4r::FileOutputter.new('GameServer', {:trunc => true , :filename => "#{$tmpDir}/test_team_log.log"})
        fileoutputter.formatter = Log4r::PatternFormatter.new({:pattern => "[%l] %d %x %m", :date_pattern => "%m-%d %H:%M:%S"})
        $log.outputters = [fileoutputter]
 
        #$log = Logger.new(STDOUT)
        #$log.level = Logger::DEBUG

        @team = OCCPGameServer::Team.new
        @team.teamname = 'TestTeam'

        $appCore = FakeCore.new
        $appCore.handler = OCCPGameServer::TestHandler.new

    end

    def test_periodic_scheduler
        # Create an event to run
        periodicevent = OCCPGameServer::TestEvent.new
        periodicevent.frequency = 1.0
        periodicevent.endtime = 8
        periodicevent.ipaddress = nil
        @team.periodicList << periodicevent

        numberOfEvents = periodicevent.frequency * periodicevent.endtime

        teamThr = Thread.new { @team.run($appCore) }
        $appCore.gameclock.start
        @team.INBOX << OCCPGameServer::GMessage.new({:signal=>'COMMAND',:fromid=>'T',:msg=>{:command=>'STATE',:state=>OCCPGameServer::RUN}})
        sleep(10)
        @team.INBOX << OCCPGameServer::GMessage.new({:signal=>'COMMAND',:fromid=>'T',:msg=>{:command=>'STATE',:state=>OCCPGameServer::STOP}})

        teamThr.join

        countEvents = 0

        while !$appCore.INBOX.empty?

            msg = $appCore.INBOX.pop
            if msg.signal === 'EVENTLOG'
                assert_equal(msg.msg[:status], OCCPGameServer::SUCCESS)
                countEvents += 1
            end
        end
        assert_equal(numberOfEvents, countEvents)

    end

end
