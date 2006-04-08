#!/usr/bin/ruby

require 'rubygems'
require_gem 'camping', '>=1.4'
require 'camping/session'

Camping.goes :PatchWatch

DATEFORMAT = "%Y-%m-%d %H:%M:%S"

module PatchWatch
    include Camping::Session
end

module PatchWatch::Models
    def self.schema(&block)
        @@schema = block if block_given?
        @@schema
    end

    class Patch < Base
        belongs_to :author
        belongs_to :state
        has_many :comments, :order => 'date ASC'
        has_and_belongs_to_many :branches
        validates_uniqueness_of :msgid
    end
    class Author < Base
        def display_name
            name || email
        end
    end
    class Comment < Base; belongs_to :patch; belongs_to :author end
    class State < Base; validates_uniqueness_of :name end
    class Admin < Base; validates_uniqueness_of :username end
    class Branch < Base; has_and_belongs_to_many :patches end
end

PatchWatch::Models.schema do
    create_table :patchwatch_patches, :force => true do |t|
        t.column :id,         :integer, :null => false
        t.column :name,       :string,  :limit => 255
        t.column :filename,   :string,  :limit => 255
        t.column :date,       :datetime
        t.column :content,    :text
        t.column :msgid,      :string,  :limit => 255
        t.column :author_id,  :integer, :null => false
        t.column :state_id,   :integer, :default => 1
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
        t.column :date,       :datetime
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
    create_table :patchwatch_branches, :force => true do |t|
        t.column :id,         :integer, :null => false
        t.column :name,       :string, :limit => 25
        t.column :created_at, :timestamp
    end
    create_table :patchwatch_branches_patches, :force => true do |t|
        t.column :patch_id,   :integer, :null => false
        t.column :branch_id,  :integer, :null => false
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
    execute "INSERT INTO patchwatch_branches (name) VALUES ('stable')"
    execute "INSERT INTO patchwatch_branches (name) VALUES ('unstable')"
    execute "INSERT INTO patchwatch_branches_patches (patch_id, branch_id) VALUES (1, 1)"
    execute "INSERT INTO patchwatch_branches_patches (patch_id, branch_id) VALUES (1, 2)"
end

module PatchWatch::Controllers
    class Index < R '/'
        def get
            @search_term = input.q
            @patches = Patch.find :all,
                                  :conditions => ['name LIKE ?', "%#{input.q}%" || "%"],
                                  :order => 'date DESC'
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
            @branches = Branch.find :all
            @has_branches = {}
            @patch.branches do |b|
                @has_branches[b.id] = true
            end
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
        def post
            @patch = Patch.find input.patch_id
            puts "patch: #{@patch}"
            p input
            redirect View, @patch
        end
    end
end

module PatchWatch::Views
    def layout
        html do
            head do
                title 'Patches'
                link :rel => 'stylesheet', :type => 'text/css',
                     :href => '/style.css', :media => 'screen'
            end
            body do
                div.content do
                    self << yield
                end
            end
        end
    end

    def index
        h1.header { a 'Patches', :href => R(Index) }

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
                        td(patch.date() || "N/A")
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
        h1.header { a "Patch: #{@patch.name}", :href => R(Index) }

        _auth
        _patch_header

        h2 'Comments'
        @comments = @patch.comments
        _comments

        h2 'Patch'
        _patch
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

    def _comments
        @comments.each do |c|
            div.comment do
                div.meta do
                    uri = "mailto:#{c.author.email}"
                    capture {a c.author.display_name, :href => "mailto:#{c.author.email}"} +
                        c.date.strftime(DATEFORMAT)
                    #p do a c.author.display_name, :href => "mailto:#{c.author.email}"
                    #    c.date
                    #end
                end
                pre.content do
                    p c.content
                end
            end
        end
    end

    def _patch_header
        form :action => R(Edit), :method => 'post' do
            table.patchmeta do
                author = @patch.author
                tr { th 'Submitter' ; td { a author.display_name, :href => "mailto:#{author.email}" } }
                tr { th 'Date'      ; td @patch.date }
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
                    tr { th 'Branches' ; td do
                        @branches.each do |b|
                            input b.name, :type => 'checkbox', :name => "branch[#{b.id}]", :value => @has_branches[b.id]
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
    end

    def _patch
        div.patch do
            pre.content { @patch.content }
        end
    end
end

def PatchWatch.create
    Camping::Models::Session.create_schema
    unless PatchWatch::Models::Patch.table_exists?
        ActiveRecord::Schema.define(&PatchWatch::Models.schema)
    end
end

def PatchWatch.connect
    PatchWatch::Models::Base.establish_connection :adapter => 'sqlite3', :database => 'patchwatch.db'
    PatchWatch::Models::Base.logger = Logger.new('patchwatch.log')
    PatchWatch::Models::Base.threaded_connections = false
    PatchWatch.create
end

if $0 == __FILE__
    require 'mongrel/camping'

    PatchWatch.connect

    server = Mongrel::Camping::start("0.0.0.0", 3301, "/patchwatch", PatchWatch)
    puts "Server running on localhost:3301"
    server.run.join
end
