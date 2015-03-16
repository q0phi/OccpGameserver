module OCCPGameServer

    require 'fiddle'

    #find libc
    x86_64 ='/lib/x86_64-linux-gnu/libc.so.6'
    i386 = '/lib/i386-linux-gnu/libc.so.6'

    if File.exist?(x86_64)
        libc6 = Fiddle.dlopen(x86_64)
    elsif File.exist?(i386)
        libc6 = Fiddle.dlopen(i386)
    else
        raise Error, "cannot support namespace shifting"
    end

    #p libc6['CLONE_NEWNET']

    $setns = Fiddle::Function.new(
            libc6['setns'],
            [Fiddle::TYPE_INT, Fiddle::TYPE_INT],
            Fiddle::TYPE_INT
    )

end
