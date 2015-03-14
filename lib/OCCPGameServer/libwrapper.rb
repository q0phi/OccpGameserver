module OCCPGameServer

    require 'fiddle'

    libc6 = Fiddle.dlopen('/lib/x86_64-linux-gnu/libc.so.6')

    #p libc6['CLONE_NEWNET']

    $setns = Fiddle::Function.new(
            libc6['setns'],
            [Fiddle::TYPE_INT, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT
    )

end
