module OCCPGameServer

    # This class handles all of the score calculations and what-nots
    class Score

        attr_accessor :labels, :names, :ScoreLabel, :ScoreName
        def initialize

            @ScoreLabel = Struct.new(:name, :raw_sql, :prepared_sql) do

                def get_sql
                    sql = "SELECT SUM(value) FROM SCORES WHERE groupname='#{name}'"
                    if not select.nil?
                        sql = "SELECT #{select} FROM SCORES"
                        if not where.nil?
                            sql += " WHERE #{where}"
                        end
                    elsif not calculation.nil?
                        sql = calculation
                    end
                    sql
                end
            end

            @ScoreName = Struct.new(:name, :lname, :formula, :descr) do
            end

            @labels = Array.new
            @names = Array.new

        end

        def get_labels
            @labels.map{|label| label.name}
        end
        def get_names
            @names.map{|name| name.name}
        end
        def get_scores
            @names
        end


        def get_score(name)
            # Evaluate the score in a separate binding context
            b = binding
            #Look up the formula for this scorename
            formula = nil
            finalScore = nil
            @names.each{ |scoreName|
                if scoreName.name == name
                    formula = scoreName.formula
                    break
                end
            }
            if formula
                #Get each component of the formula from their corresponding labels
                $db.transaction { |selfs|
                    @labels.each { |e|
                        if formula.match( e[:name] )
                            res = e.prepared_sql.execute!

                            $log.warn("Score-label #{e[:name]} SQL definition returning more than 1 row".yellow) if res.length > 1

                            result = res[0][0] # Row 0 Column 0
                            if result
                                b.local_variable_set(e[:name], result)
                            elsif
                                b.local_variable_set(e[:name],0.0)
                            end
                        end
                    }
                }

                begin
                    score = eval( formula , b ).to_f
                    if score.infinite?
                        $log.warn "Score #{name} formula results in infinite score"
                        finalScore = 0.0
                    elsif !score.nan?
                        finalScore = score
                    else
                        finalScore = 0.0
                    end
                rescue ZeroDivisionError => e
                    $log.warn "Score #{name} formula is invalid #{e.message}".yellow
                end

            else
                $log.error "Score #{name} formula not defined"
            end

            return finalScore
        end # End Get Score

        def cleanup

            @labels.each{|label|
                label.prepared_sql.close
                $log.debug "Point-label #{label.name} SQL statement closed."
            }

        end

        def generate_statistics(gametime)
            # Evaluate the score in a separate binding context
            b = binding

            finalScore = nil
            @names.each{ |scoreName|
                formula = nil
                formula = scoreName.formula

                if formula

                    #Get each component of the formula from their corresponding labels
                    $db.transaction { |selfs|
                        @labels.each { |e|
                            if formula.match( e[:name] )
                                pointLabel = e.prepared_sql.execute!

                                $log.warn("Point-label #{e[:name]} SQL definition returning more than 1 row".yellow) if pointLabel.length > 1

                                labelValue = pointLabel[0][0] # Row 0 Column 0
                                if labelValue
                                    b.local_variable_set(e[:name], labelValue)
                                elsif
                                    #if the point-label is not curerntly set treat it like 0 points
                                    b.local_variable_set(e[:name], 0.0)
                                end
                            end
                        }
                    }

                    begin
                        score = eval( formula , b ).to_f
                        if score.infinite?
                            $log.warn "Score #{name} formula resulted in infinite score, treating as zero value".yellow
                            finalScore = 0.0
                        elsif !score.nan?
                            timeT = Time.now.to_i
                            # Record a valid value in the database
                            $db.execute("INSERT INTO scoredata VALUES (?,?,?,?)", [timeT, gametime, scoreName.name, score])
                            $log.debug "Database insert"
                        else
                            finalScore = 0.0
                        end
                    rescue ZeroDivisionError => e
                        $log.warn "Score #{name} formula is invalid #{e.message}".yellow
                    end

                else
                    $log.error "Score #{name} formula not defined"
                end

            }
        end # End generate_statistics

        #Return the statistics requested
        def get_score_stats( scorename, opts = {} )

            # opts = { :gametime => 0, :length => 0, :resolution => 0 }

            # If the scorename is not provided return a failuire
            if scorename.empty?
                return false
            end

            if not opts[:gametime]
                opts[:gametime] = -1
            end
            if not opts[:length]
                opts[:length] = 600
            end

            #Begin building the query we need
            query = "SELECT gametime, value FROM scoredata where scorename = ?"

            endtime = ''
            starttime = ''
            if opts[:gametime] != -1
                endtime = " and gametime < #{opts[:gametime]}"
            end

            if opts[:length] > 0
                if opts[:gametime] != -1
                    sTime = opts[:gametime] - opts[:length]
                else
                    sTime = $appCore.gameclock.gametime - opts[:length]
                end
                if sTime >= 0
                    starttime = " and gametime > #{sTime}"
                end
            end

            query = query + starttime + endtime + " order by gametime"

            $log.debug "Score Stats Query: " + query

            output =[]
            if true
                statsData = $db.execute(query, [scorename])
                output = statsData
                # statsData.each do |row|
                #     output << row[0], row[1]
                # end
            end

            return output
        end

    end #end Class
end #End Module
