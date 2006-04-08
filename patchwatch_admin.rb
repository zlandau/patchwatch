require 'patchwatch'

PatchWatch.connect

def handle_arguments(args)
    cmd = args.shift

    case cmd
    when 'addadmin'
        name = args.shift or fail 'invalid username'
        password = args.shift or fail 'invalid password'
        PatchWatch::Models::Admin.create!(:username => name, :password => password)
    when 'rmadmin'
        name = args.shift or fail 'invalid username'
        count = PatchWatch::Models::Admin.delete_all(['username = ?', name])
        if count == 0 then fail 'no match found' end
    when 'addbranch'
        name = args.shift or fail 'invalid branch name'
        PatchWatch::Models::Branch.create!(:name => name)
    when 'rmbranch'
        name = args.shift or fail 'invalid branch name'
        count = PatchWatch::Models::Branch.delete_all(['name = ?', name])
        if count == 0 then fail 'no match found' end
    else
        fail 'invalid command'
    end
end

handle_arguments(ARGV)
