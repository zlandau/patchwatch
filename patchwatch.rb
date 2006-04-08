#!/usr/bin/ruby

require 'rubygems'
require_gem 'camping', '>=1.4'
require 'camping/session'

Camping.goes :PatchWatch

module PatchWatch
    include Camping::Session
end

module PatchWatch::Models
    def self.schema(&block)
        @@schema = block if block_given?
        @@schema
    end

    class Patch < Base; belongs_to :author; belongs_to :state; has_many :comments end
    class Author < Base
        def display_name
            name || email
        end
    end
    class Comment < Base; belongs_to :patch; belongs_to :author end
    class State < Base; end
    class Admin < Base; end
end

PatchWatch::Models.schema do
    create_table :patchwatch_patches, :force => true do |t|
        t.column :id,         :integer, :null => false
        t.column :name,       :string,  :limit => 255
        t.column :filename,   :string,  :limit => 255
        t.column :content,    :text
        t.column :msgid,      :string,  :limit => 255
        t.column :author_id,  :integer, :null => false
        t.column :state_id,   :integer, :null => false
        t.column :created_at, :timestamp
    end
    create_table :patchwatch_authors, :force => true do |t|
        t.column :id,         :integer, :null => false
        t.column :email,      :string,  :limit => 255
        t.column :name,       :string,  :limit => 255
        t.column :created_at, :timestamp
    end
    create_table :patchwatch_comments, :force => true do |t|
        t.column :id,         :integer, :null => false
        t.column :author_id,  :integer, :null => false 
        t.column :patch_id,   :integer, :null => false
        t.column :content,    :text
        t.column :created_at, :timestamp
    end
    create_table :patchwatch_states, :force => true do |t|
        t.column :id,         :integer, :null => false
        t.column :name,       :string,  :limit => 20
        t.column :created_at, :timestamp
    end
    create_table :patchwatch_admins, :force => true do |t|
        t.column :id,         :integer, :null => false
        t.column :username,   :string,  :limit => 255
        t.column :password,   :string,  :limit => 255
        t.column :created_at, :timestamp
    end

    execute "INSERT INTO patchwatch_states (name) VALUES ('New')"
    execute "INSERT INTO patchwatch_states (name) VALUES ('Pending Review')"
    execute "INSERT INTO patchwatch_authors (email, name) VALUES ('kapheine@divineinvasion.net', 'Zachary P. Landau')"
    execute "INSERT INTO patchwatch_authors (email) VALUES ('bob@hope.com')"
    execute "INSERT INTO patchwatch_patches (name, filename, content, msgid, author_id, state_id) VALUES ('A patch', 'somepatch.dpatch', 'And this is the patch', 'msgid1234', 1, 1)"
    execute "INSERT INTO patchwatch_comments (author_id, patch_id, content) VALUES (1, 1, 'Some comment')"
    execute "INSERT INTO patchwatch_patches (name, filename, content, msgid, author_id, state_id) VALUES ('Another patch', 'another.dpatch', 'Some contents', 'msgid1235', 2, 2)"
    execute "INSERT INTO patchwatch_comments (author_id, patch_id, content) VALUES (2, 2, 'Blah Blah')"
    execute "INSERT INTO patchwatch_comments (author_id, patch_id, content) VALUES (1, 2, 'More crap')"
    execute "INSERT INTO patchwatch_admins (username, password) VALUES ('kapheine', 'pw')"
end

module PatchWatch::Controllers
    class Index < R '/'
        def get
            @search_term = input.q
            @patches = Patch.find :all, :conditions => ['name LIKE ?', "%#{input.q}%" || "%"]
            render :index
        end
    end

    class Style < R '/style.css'
        def get
            @headers["Content-Type"] = "text/css; charset=utf-8"
            @body = File.read("style.css")
        end
    end

    class View < R '/view/(\d+)'
        def get patch_id
            @patch = Patch.find patch_id
            @logged_in = !@state.admin_id.blank?
            @states = State.find :all
            render :view
        end
    end

    class Download < R '/download/(\d+)'
        def get patch_id
            @patch = Patch.find patch_id
            @headers["Content-Type"] = "text/x-patch"
            @body = @patch.content
        end
    end

    class Login
        def get
            _login
        end

        def post
            @admin = Admin.find :first, :conditions => ['username = ? AND password = ?', input.username, input.password]

            if @admin
                @state.admin_id = @admin.id
                redirect Index
            else
                @state.error = "Login Failure"
                redirect Login
            end
        end
    end

    class Logout
        def get
            @state.admin_id = nil
            redirect Index
        end
    end

    class Edit
    end
end

module PatchWatch::Views
    def layout
        html do
            head do
                title 'Darcs / Patches'
                link :rel => 'stylesheet', :type => 'text/css',
                     :href => '/style.css', :media => 'screen'
            end
            body do
                h1.header { a 'Darcs Patches', :href => R(Index) }
                div.content do
                    self << yield
                end
            end
        end
    end

    def index
        _auth
        _search

        br

        if @search_term
            a 'Back to list', :href => R(Index)
            br
        end

        unless @patches.empty?
            columns = %w{Patch Date Author State}

            odd = false

            table.patchlist do
                tr { columns.each { |c| th c } }
                @patches.each do |patch|
                    tr :class => ((odd and "odd") or "even") do
                        td { a patch.name, :href => R(View, patch) }
                        td(patch.created_at() || "N/A")
                        td { a patch.author.display_name,
                             :href => "mailto:#{patch.author.email}" }
                        td patch.state.name
                    end
                    odd = !odd
                end
            end
        else
            p "No patches found."
        end
    end

    def view
        _auth

        form :action => R(Edit), :method => 'post' do
            table.patchmeta do
                author = @patch.author
                tr { th 'Submitter' ; td { a author.display_name, :href => "mailto:#{author.email}" } }
                tr { th 'Date'      ; td @patch.created_at }
                tr { th 'Message ID'; td @patch.msgid }
                tr { th 'Download'  ; td { a @patch.filename, :href => R(Download, @patch.id) } }
                if @logged_in
                    tr { th 'State' ; td do
                        tag! :select, :id => 'state_id' do
                            @states.each do |s|
                                #tag! :option, s.name, :value => s.id, :selected => true
                                if s.id == 1
                                    tag! :option, s.name, :value => s.id
                                else
                                    tag! :option, s.name, :value => s.id, :selected =>nil 
                                end
                            end
                        end
                    end }
                else
                    tr { th 'State'     ; td @patch.state.name }
                end

                input :type => 'hidden', :name => 'patch_id', :value => @patch.id
            end
            if @logged_in
                input :type => 'submit', :value => 'Update'
            end
        end

        h2 'Comments'
        @patch.comments.each do |c|
            div.comment do
                div.meta do
                    p { a c.author.display_name, :href => "mailto:#{c.author.email}" }
                    pd c.created_at
                end
                pre.content do
                    p c.content
                end
            end
        end

        h2 'Patch'
        div.patch do
            pre.content { @patch.content }
        end
    end

    def _auth
        div.auth do
            if @state.admin_id.blank? 
                a 'Login', :href => R(Login)
            else
                a 'Logout', :href => R(Logout)
            end
        end
    end

    def _login
        if @state.error
            p @state.error
            @state.error = nil
        end

        form :action => R(Login), :method => 'post' do
            label 'Username:', :for => 'username'
            input :name => 'username', :type => 'text'; br

            label 'Password:', :for => 'password'
            input :name => 'password', :type => 'text'; br

            input :type => 'submit', :name => 'login', :value => 'Login'
        end
    end

    def _search
        div.search do
            form :action => R(Index), :method => 'get' do
                input :name => 'q', :type => 'text', :value => @search_term
                input :type => 'submit', :value => 'search'
            end
        end
    end
end

def PatchWatch.create
    Camping::Models::Session.create_schema
    unless PatchWatch::Models::Patch.table_exists?
        ActiveRecord::Schema.define(&PatchWatch::Models.schema)
    end
end

if __FILE__ == $0
    require 'mongrel/camping'

    PatchWatch::Models::Base.establish_connection :adapter => 'sqlite3', :database => 'patchwatch.db'
    PatchWatch::Models::Base.logger = Logger.new('patchwatch.log')
    PatchWatch::Models::Base.threaded_connections = false
    PatchWatch.create

    server = Mongrel::Camping::start("0.0.0.0", 3301, "/patchwatch", PatchWatch)
    server.run.join
end
