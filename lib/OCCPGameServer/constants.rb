module OCCPGameServer

    #
    # Valid Challenge Run States
    #
    WAIT = 1
    READY = 2
    RUN = 3
    STOP = 4
    QUIT = 5

    #
    # Event Status Return Codes
    #
    SUCCESS = 'SUCCEED'
    FAILURE = 'FAIL'
    UNKNOWN = 'UNKNOWN'

    STATISTICS_RESOLUTION_DEFAULT = 10
    STATISTICS_RESOLUTION_WARNING = 300

end
