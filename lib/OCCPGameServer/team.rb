module OCCPGameServer

    class Team

        attr_accessor :teamname, :speedfactor, :teamhost

        def initialize()

            #Create an Instance variable to hold our events
            @events = Array.new
            
            @rawevents = Array.new


        end

        # Push a new event into our list
        def add_event(new_event)
            @events << new_event
        end
        
        # Push a new raw unprocessed event into our list
        def add_raw_event(new_event)
            @rawevents << new_event
        end

        def get_raw_events()
            @rawevents
        end

        def run(parent_main)

            puts @teamname + " Executing..."
           
            
            #Validate each event
            # @rawevents list is an array of event lists
            @rawevents.each {|eventlist|
                eventlist.find('team-event').each {|event|
                    
                    #First Identify the handler
                    handler_name = event.find("handler").first.attributes["name"]
                   
                    event_handler = parent_main.get_handler(handler_name)

                    this_event = event_handler.parse_event(event)

                    @events << this_event

                }
            
            }
            
            #Signal ready and wait for start signal


            puts @teamname + " Finished Executing."
        end
    end

end
