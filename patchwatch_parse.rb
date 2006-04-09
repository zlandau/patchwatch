require 'patchwatch'
require 'rmail'
require 'ostruct'
require 'date'

SUBJECT_PREFIX = "\[darcs-devel\] "
MIME_PATCH = %w(text/x-patch text/x-darcs-patch)
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

def is_patch?(part)
    MIME_PATCH.include? part.header.content_type
end

def is_comment?(part)
    #puts "BEGIN #{part.body.to_s} END"
    (MIME_COMMENTS.include? part.header.content_type) && (part.body.to_s != IGNORE_BLOCK)
end

def parse_references(refs)
    refs.split("\n\t")
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
        p.body = clean_body(message.body, IGNORE_BLOCK)
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
        if is_comment?(part) or is_patch?(part)
            data = OpenStruct.new
            data.date = date
            data.content = clean_body(part.body, IGNORE_BLOCK)
            data.references = references
            data.author = author
            data.msgid = msgid

            if is_patch?(part)
                data.name = subject
                patches << data
            elsif is_comment?(part)
                comments << data
            end
        end
    end

    return patches, comments
end

def get_author(author)
    a = PatchWatch::Models::Author.find_by_email(author.email)
    return a if a
    return PatchWatch::Models::Author.create(:email => author.email, :name => author.name)
end

def add_patch(patch)
    PatchWatch::Models::Patch.transaction do
        author = get_author(patch.author)

        # If the patch exists, we silently ignore it
        if not PatchWatch::Models::Patch.find_by_msgid(patch.msgid)
            PatchWatch::Models::Patch.create!(:name    => patch.name,
                                              :date    => patch.date,
                                              :content => patch.content,
                                              :msgid   => patch.msgid,
                                              :author  => author)
        end
    end
end

def add_comment(comment)
    PatchWatch::Models::Comment.transaction do
        patches = []

        # If the comment was part of the patch email..
        p = PatchWatch::Models::Patch.find_by_msgid(comment.msgid)
        if p then patches << p end

        # If the comment was a reply to the patch email..
        comment.references.each do |ref|
            p = PatchWatch::Models::Patch.find_by_msgid(ref)
            if p then patches << p end
        end

        # XXX: If multiple references are found, we add a copy of the comment to each
        # patch.  I'm not sure if this is what we want or not
        patches.each do |p|
            PatchWatch::Models::Comment.create!(:author_id => get_author(comment.author).id,
                                                :patch_id  => p.id,
                                                :date      => comment.date,
                                                :content   => comment.content)
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

