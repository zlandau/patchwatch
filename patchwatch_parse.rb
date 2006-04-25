require 'patchwatch'
require 'rmail'
require 'ostruct'
require 'date'
require 'patchinfo'

SUBJECT_PREFIX = "\[darcs-devel\] "
PLAIN_PATCH = %w(text/x-patch)
DARCS_PATCH = %w(text/x-darcs-patch)
MIME_COMMENTS = %w(text/plain)
IGNORE_BLOCK =<<HERE
_______________________________________________
darcs-devel mailing list
darcs-devel@darcs.net
http://www.abridgegame.org/cgi-bin/mailman/listinfo/darcs-devel
HERE

input = STDIN

def clean_subject(txt, header)
    txt.gsub("\n", " ").gsub("\t", " ").gsub("Re: ", "").gsub(header, "").squeeze(" ")
end

def clean_body(txt, header)
    RMail::Utils.quoted_printable_decode(txt.gsub(header, ""))
end

def is_plain_patch?(part)
    PLAIN_PATCH.include? part.header.content_type
end

def is_darcs_patch?(part)
    DARCS_PATCH.include? part.header.content_type
end

def is_comment?(part)
    (MIME_COMMENTS.include? part.header.content_type) && (part.body.to_s != IGNORE_BLOCK)
end

def parse_references(refs)
    refs.split("\n\t")
end

def parse_filename(contenttype)
    ma = contenttype.match(/name="([^"]*)"/)
    return ma ? ma[1] : "unnamed"
end

def parse_darcs_patches(references, msgid, part)
    patches = []

    full_body = clean_body(part.body, IGNORE_BLOCK)

    begin
        fd = StringIO.new(full_body)
        3.times { fd.readline }

        loop do
            patchinfo = Darcs::PatchInfo.read(fd)
            body = ""
            line = nil
            body += line while !((line = fd.readline) =~ /^\}/)
            patch = OpenStruct.new
            patch.name = patchinfo.name
            patch.date = patchinfo.timestamp
            patch.msgid = msgid
            patch.altid = patchinfo.filename[0..-4]
            patch.dlcontent = full_body
            patch.filename = parse_filename(part.header["Content-Type"])

            ra = RMail::Address.parse(patchinfo.author)
            author = OpenStruct.new
            author.email = ra.first.address
            author.name = ra.first.name

            patch.author = author
            patch.content = body
            patches << patch
        end
    rescue => e
        puts e
    end

    patches
end

def parse_message(message)
    patches = []
    comments = []

    msg_header = message.header

    parts = []
    if message.multipart?
        message.each_part { |p| parts << p }
    else
        p = OpenStruct.new
        p.header = message.header
        p.body = message.body
        parts << p
    end

    header = message.header

    author = OpenStruct.new
    author.email = header.from.first.address
    author.name = header.from.first.name
    date = header.date
    references = header["References"] ? parse_references(header["References"]) : []
    msgid = header.message_id
    subject = clean_subject(header.subject, SUBJECT_PREFIX)

    # This is fucking awful.  But I'm sick of dealing with this
    # This will do one level of message part flattening
    all_parts = parts
    more = []
    all_parts.each do |part|
        if part.multipart? then
            part.each_part { |p| more << p }
        end
    end
    all_parts.concat more
    
    all_parts.each do |part|
        if is_comment?(part) or is_plain_patch?(part)
            data = OpenStruct.new
            data.date = date
            data.references = references
            data.msgid = msgid
            data.content = clean_body(part.body, IGNORE_BLOCK)
            data.author = author

            if is_plain_patch?(part)
                data.name = subject
                data.filename = parse_filename(part.header["Content-Type"])
                patches << data
            elsif is_comment?(part)
                comments << data
            end
        elsif is_darcs_patch?(part)
            patches.concat parse_darcs_patches(references, msgid, part)
        end
    end

    return patches, comments
end

def get_author(author)
    a = PatchWatch::Models::Author.find_by_email(author.email)
    return a if a
    return PatchWatch::Models::Author.create(:email => author.email, :name => author.name)
end

def get_msgid(name)
    msgid = PatchWatch::Models::Msgid.find_by_name(name)
    return msgid if msgid
    return PatchWatch::Models::Msgid.create(:name => name)
end

def add_patch(patch)
    PatchWatch::Models::Patch.transaction do
        author = get_author(patch.author)

        if not PatchWatch::Models::Patch.exist? patch
            # Find any patches that are not a repost but have the same name and
            # author.  We assume this means that a patch has been fixed up and
            # re-posted.  Mark all the previous ones as superseded by the new
            # one.
            superseded = PatchWatch::Models::Patch.find :all,
                :conditions => ['name = ? AND author_id = ?',
                    patch.name, author.id]
            state = PatchWatch::Models::State.find_by_name("Superseded")
            superseded.each do |s|
                s.state = state
                s.save
            end

            # Now create the patch
            p = PatchWatch::Models::Patch.create!(:name     => patch.name,
                                                  :filename => patch.filename,
                                                  :date     => patch.date,
                                                  :content  => patch.content,
                                                  :dlcontent => patch.dlcontent,
                                                  :altid    => patch.altid,
                                                  :author   => author)

        else
            # Otherwise, grab the already-existing patch
            p = PatchWatch::Models::Patch.find_by_altid(patch.altid)
        end

        msgid = get_msgid(patch.msgid)
        found = p.msgids.find :first, :conditions => ["name = ?", patch.msgid]
        if not found
            # If there is not already a link between this msgid and this patch,
            # add it
            PatchWatch::Models::Patch.connection.execute("insert into patchwatch_msgids_patches (msgid_id, patch_id) VALUES (#{msgid.id}, #{p.id})")
        end
    end
end

def add_comment(comment)
    PatchWatch::Models::Comment.transaction do
        # Create the comment
        c = PatchWatch::Models::Comment.create!(:author_id => get_author(comment.author).id,
                                                :date      => comment.date,
                                                :content   => comment.content)

        # If the comment was part of the patch email..
        msgid = nil
        msgid = PatchWatch::Models::Msgid.find_by_name(comment.msgid)
        if msgid
            # TODO: Do this using Active Record
            msgid.patches.each do |p|
                PatchWatch::Models::Patch.connection.execute("insert into patchwatch_comments_patches (patch_id, comment_id) VALUES (#{p.id},#{c.id})")
            end
        end

        # If the comment was a reply to the patch email..
        comment.references.each do |ref|
            msgid = PatchWatch::Models::Msgid.find_by_name(ref)
            if msgid
                # TODO: Again, use Active Record
                msgid.patches.each do |p|
                    PatchWatch::Models::Patch.connection.execute("insert into patchwatch_comments_patches (patch_id, comment_id) VALUES (#{p.id}, #{c.id})")
                end
            end
        end
    end
end

patches = []
comments = []

RMail::Mailbox::MBoxReader.new(input).each_message do |entry|
    message = RMail::Parser.read(entry)
    new_patches, new_comments = parse_message(message)
    patches.concat new_patches
    comments.concat new_comments
end

PatchWatch.connect
patches.each { |p| add_patch(p) }
comments.each { |c| add_comment(c) }

