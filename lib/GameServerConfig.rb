module GameServerConfig

    Listen_address="0.0.0.0"
    Listen_port="24365"

    ##
    # The network namespace lifetime specifies how long after 
    # a refcount reaches zero that the namespace should be held onto 
    # for re-use by other events
    NETNS_LIFETIME = 30 #seconds


end
