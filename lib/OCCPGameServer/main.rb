module OCCPGameServer

    class Main

        attr_accessor :gameclock, :networkid, :scenarioname, :INBOX, :eventRunQueue
        attr_accessor :STATE, :db, :scoreKeeper, :interfaces, :ipPools
        attr_accessor :gameid, :type, :description, :scenariouid, :statsResolution
        attr_reader :teams, :begintime, :endtime

        def initialize
            @events = {}
            @hosts = Array.new

            @teams = Array.new
            @localteams = Array.new

            #Run queue for event that have been launched by a ascheduler
            @eventRunQueue = Queue.new

            @STATE = WAIT
            @INBOX = Queue.new
            @db = ''
            @handlers= Array.new
            @gameclock = GameClock.new
            @scoreKeeper = Score.new

            @interfaces = Array.new     #{:name=>'eth0', :network=>'pub1'}
            @ipPools = {}               #{"poolName" => {poolHash}, ... }
            @nsPool = Array.new
            @nsRegistry = IPTools::NetNSRegistry.new

            @begintime = nil
            @endtime = nil
        end

        def add_event()
        end

        #Add a team host to the list
        def add_host(new_host)
            @hosts.push(new_host)
        end

        def add_team(new_team)
            @teams.push(new_team)
        end

        #Store each of the event handlers to be dispatched
        def add_handler(new_handler)
            @handlers.push(new_handler)
        end

        # Lookup a handler by name to get its information
        def get_handler(handle_name)
            return @handlers.find {|handler| handler.name == handle_name }
        end

        def get_handlers()
            @handlers
        end

        def get_network(name)
            return @interfaces.find{|netName| netName[:network] == name }
        end

        def get_ip_pool(name)
            return @ipPools[name]
        end

        ##
        # Return a network namespace for the given network segment
        # If the ip address may either be a valid address or pool name
        # netInfo = {iface, ipaddr, cidr, gateway}
        def get_netns(netInfo)

          netns = @nsRegistry.get_registered_netns(netInfo)
          #  if !@ipPools.member?(ipaddr)

          #      netns = @nsRegistry.get_registered_netns(netInfo)
          #
          #  else
          #      # Choose a random ip address
          #      pool = @ipPools[ipaddr]
          #      if pool.nil? || pool.empty?
          #          return nil
          #      end
          #      netInfo = {:iface => networkSegment, :ipaddr => pool[rand(pool.length)], :cidr => pool[:cidr], :gw => pool[:gw] }

          #      netns = @nsRegistry.get_registered_netns(netInfo)
          #  end

            return netns
        end

        ##
        # Release the name space when not using it
        #
        def release_netns(netnsName)
            @nsRegistry.release_registered_netns(netnsName)
        end

        def set_state(state)

            case state
            when WAIT
                if @STATE == RUN
                    $log.info 'Instance PAUSE Triggered'.yellow
                    @teams.each { |team|
                        team.INBOX << GMessage.new({:fromid=>'Main Thread',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> WAIT}})
                    }
                    @gameclock.pause
                end
            when RUN
                if @begintime == nil
                    @begintime = Time.now
                end
                @gameclock.resume
                @teams.each { |team|
                    team.INBOX << GMessage.new({:fromid=>'Main Thread',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> RUN}})
                    #team.set_state(state)
                }
                $log.info 'Instance RESUME Triggered'.yellow
            when STOP
                #Clean everything up and signal all process to stop
                @teams.each { |team|
                    team.INBOX << GMessage.new({:fromid=>'Main Thread',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> STOP}})
                }
                @gameclock.pause
                if @endtime == nil
                    @endtime = Time.now
                end
            when QUIT
                @teams.each { |team|
                    team.INBOX << GMessage.new({:fromid=>'Main Thread',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> STOP}})
                }
                @gameclock.pause
                if @endtime == nil
                    @endtime = Time.now
                end
                exit_cleanup()

            end

            @STATE = state

            #Update the stats generator when changing states
            @scoreStats.wakeup

        end
        def get_state()
            return @STATE
        end

        #Cleanup any residuals and wait for related threads to shutdown nicely
        def exit_cleanup()

            threadRelease = false

            while not threadRelease
                # Poll each thread until there all dead
                if @localteams.empty?
                    threadRelease = true
                end

                @localteams.delete_if{|evThread|
                    not evThread[:thr].alive?
                }

            end

            # Cleanup network namespaces; Add a single namespace to supress error if none specified
            #system("ip netns list | awk '{print $0;}'| xargs -L 1 ip netns delete")
            pid = spawn("ip netns add occp_cleanup")
            Process.wait pid
            pid = spawn("ip netns list | grep occp_ | xargs -L 1 ip netns delete")
            Process.wait pid

            $log.debug 'Team threads cleanup complete'

        end

        # Entry point for the post-setup code
        def run ()
            Log4r::NDC.push('Main:')

            #Launch each teams scheduler
            @teams.each { |team|
                if team.teamhost == "localhost"
                    @localteams << {:teamid=>team.teamid, :thr=> Thread.new { team.run(self) }}
                else
                    #lookup the connection information for this team and dispatch the team
                end
            }

            @scoreStats = Thread.new do
                Log4r::NDC.push('Stats:')
                $log.debug "Stats Thread Startup"
                while @STATE != STOP or @STATE != QUIT
                    if @STATE == RUN
                        $log.debug "Generating Data"
                        @scoreKeeper.generate_statistics(@gameclock.gametime)
                        sleep(@statsResolution)
                    elsif @STATE == WAIT or @STATE == READY
                        $log.debug "Sleeping while not in RUN state"
                        sleep
                    end
                end
                $log.debug "Stats Thread Shutdown"
            end

            #Wait till all the teams are ready
            @STATE = READY

            #Poll the @INBOX waiting for tasks
            while @STATE != QUIT and message = @INBOX.pop do

                case message.signal

                #Dump Messages to the Screen only
                when 'CONSOLE'
                    puts message.fromid.to_s.yellow + " " + message.msg.to_s
                    # from = message.fromid.to_s
                    # $log.info(from + ": " + message.msg.to_s)

                #Dump Messages to the Screen and into the logfile
                when 'CONSOLELOG'
                    puts message.fromid.to_s.yellow + " " + message.msg.to_s
                    from = message.fromid.to_s
                    $log.info(from + ": " + message.msg.to_s)

                #Dump Messages into the logfile only
                when 'LOG'
                    from = message.fromid.to_s
                    $log.info(from + ": " + message.msg.to_s)

                when 'SCORE'
                    #We are receiving a score hash that should be added to the appropriate score group
                    timeT = Time.now.to_i
                    gametime = message.msg[:gametime]
                    group = message.msg[:scoregroup]
                    value = message.msg[:value]
                    eventid = message.msg[:eventid]
                    eventuid = message.msg[:eventuid]

                    $db.execute("INSERT INTO scores VALUES (?,?,?,?,?,?)", [timeT, gametime, eventid, eventuid, group, value])
                    $log.debug("Score recorded in db.score")


                when 'EVENTLOG'
                    #Log that an event was run
                    tblArray = [Time.now.to_i,
                        message.msg[:starttime],
                        message.msg[:endtime],
                        message.msg[:handler],
                        message.msg[:eventname],
                        message.msg[:eventid],
                        message.msg[:eventuid],
                        message.msg[:custom],
                        message.msg[:status]
                    ]

                    $db.execute("INSERT INTO events VALUES (?,?,?,?,?,?,?,?,?);", tblArray);
                    $log.debug("Event Recorded in db.event")

                when 'COMMAND'

                    command = message.msg

                    case command[:command]
                    when 'STATE'
                        $log.debug "STATE MSG RECEIVED: #{command[:state]}"
                        set_state(command[:state])
                    when :LENGTH
                        $log.debug "Length Change MSG RECEIVED: #{command[:length]}"
                        @gameclock.set_gamelength(command[:length], 'seconds')
                    end

                when 'STATUS'
                    @teams.each { |team|
                            team.INBOX << GMessage.new({:fromid=>'Main Thread',:signal=>'STATUS'})
                    }

                when 'DIE'
                    break
                else
                    break
                end

            end #@INBOX Poll

            #wait for all the teams to finish
            $log.debug "Waiting for Team thread exit"
            @localteams.each { |team| team[:thr].join }
            $log.debug "Team thread join complete"

        end #def run

    end #Class

end #Module
