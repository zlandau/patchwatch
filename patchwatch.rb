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
        has_and_belongs_to_many :branches
        has_and_belongs_to_many :comments, :order => 'date ASC'
        has_and_belongs_to_many :msgids

        def self.exist? patch
            (find :all, :conditions => ['altid = ? AND name = ?',
                                         patch.altid, patch.name]).length > 0
        end
    end
    class Author < Base
        def display_name
            name || email
        end
    end
    class Comment < Base
        has_and_belongs_to_many :patches
        belongs_to :author
    end
    class State < Base; validates_uniqueness_of :name end
    class Admin < Base; validates_uniqueness_of :username end
    class Branch < Base; has_and_belongs_to_many :patches end
    class Msgid < Base; has_and_belongs_to_many :patches end
end

PatchWatch::Models.schema do
    create_table :patchwatch_patches, :force => true do |t|
        t.column :id,         :integer, :null => false
        t.column :name,       :string,  :limit => 255
        t.column :filename,   :string,  :limit => 255
        t.column :date,       :datetime
        t.column :content,    :text
        t.column :dlcontent,  :text
        t.column :altid,      :string,  :limit => 255
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
    create_table :patchwatch_comments_patches, :force => true do |t|
        t.column :patch_id,   :integer, :null => false
        t.column :comment_id, :integer, :null => false
        t.column :created_at, :timestamp
    end
    create_table :patchwatch_msgids, :force => true do |t|
        t.column :id,         :integer, :null => false
        t.column :name,       :string, :limit => 255
        t.column :created_at, :timestamp
    end
    create_table :patchwatch_msgids_patches, :force => true do |t|
        t.column :msgid_id,   :integer, :null => false
        t.column :patch_id,   :integer, :null => false
        t.column :created_at, :timestamp
    end

    execute "INSERT INTO patchwatch_states (name) VALUES ('New')"
    execute "INSERT INTO patchwatch_states (name) VALUES ('Under Review')"
    execute "INSERT INTO patchwatch_states (name) VALUES ('Changes Requested')"
    execute "INSERT INTO patchwatch_states (name) VALUES ('Superseded')"
    execute "INSERT INTO patchwatch_states (name) VALUES ('Accepted')"
    execute "INSERT INTO patchwatch_states (name) VALUES ('Rejected')"
    execute "INSERT INTO patchwatch_branches (name) VALUES ('stable')"
    execute "INSERT INTO patchwatch_branches (name) VALUES ('unstable')"
    execute "INSERT INTO patchwatch_admins (username, password) VALUES ('kapheine', 'pw')"
    execute "INSERT INTO patchwatch_admins (username, password) VALUES ('test', 'test')"
end

module PatchWatch::Controllers
    class Index < R '/', '/sort/([\w.]*)'
        def get order=nil
            @order_term = order
            @order = order ? order : 'date DESC'
            # Date, unlike the other orderings, should be descending
            if @order == "date" then @order += " DESC" end

            like = "%#{input.q}%" || "%"
            if input.q && !input.q.empty?
                @search_term = input.q
            else
                @search_term = nil
            end

            # I've had prouder moments...
            @patches = Patch.find_by_sql("select patch.*,author.name as author, " +
              " state.name as state,patch.date as date from patchwatch_patches  " +
              " as patch inner join patchwatch_authors as author on author.id = " +
              " patch.author_id inner join patchwatch_states as state on state.id " +
              " = patch.state_id" +
                                         " where patch.name LIKE #{Patch.quote(like)} " +
                                         " order by #{@order}")
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

    class Download < R '/download/(\d+)/(.*)'
        def get(patch_id, name)
            @patch = Patch.find patch_id
            @headers["Content-Type"] = "text/x-patch"
            @body = @patch.dlcontent || @patch.content
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

            @patch.branches.clear
            if input.branch
                @patch.branches = Branch.find_all_by_id input.branch.keys
            end
            if input.state_id
                @patch.update_attributes :state_id => input.state_id
            end

            @patch.save
            redirect View, @patch
        end
    end

    class Remote
        def post
            admin = Admin.find_by_username_and_password(input.username, input.password)

            if admin then
                patch = Patch.find_by_altid(input.altid)

                if not patch
                    fail "Invalid patch id: #{input.altid}"
                end

                if input.state
                    state = State.find_by_name(input.state)
                    if state
                        patch.state = State.find_by_name(input.state)
                        patch.save
                    else
                        fail "Invalid state #{input.state}"
                    end
                end
                if input.branches
                    branches = input.branches.split(',')
                    patch.branches.clear
                    patch.branches = Branch.find_all_by_name branches
                    patch.save
                end
            else
                fail "Incorrect username or password"
            end
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
            odd = false

            headers = [ ["Patch", "patch.name"], ["Date", "date"], ["Author", "author"],
                        ["State", "state"] ]

            table.patchlist do
                tr do
                    headers.each do |h|
                        txt, link = h[0], h[1]
                        th { if @order == link
                               span txt, :class => 'colactive'
                             else
                               a txt, :href => R(Index, link), :class => 'colinactive'
                             end
                        }
                    end
                end
                @patches.each do |patch|
                    tr :class => ((odd and "odd") or "even") do
                        td { a patch.name, :href => R(View, patch) }
                        td(patch.date() || "N/A")
                        td { a patch.author.display_name,
                             :href => "mailto:#{patch.author.email}" }
                        td patch.state.name
                        td { small { a "download", :href => R(Download, patch.id, patch.filename) } }
                    end
                    odd = !odd
                end
            end
        else
            p "No patches found."
        end
    end

    def view
        h1.header { capture { a "Patches", :href => R(Index) } + " / #{@patch.name}" }

        _auth
        br
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

        h1 'Authentication Required'
        form :action => R(Login), :method => 'post' do
            table.login do
                tr { td { label 'Username:', :for => 'username' }
                     td { input :name => 'username', :type => 'text'; br } }
                tr { td { label 'Password:', :for => 'password' }
                     td { input :name => 'password', :type => 'text'; br } }
                tr { td {}
                     td { input :type => 'submit', :name => 'login', :value => 'Login' } }
            end
        end
    end

    def _search
        if @order_term
            redir = R(Index, @order_term)
        else
            redir = R(Index)
        end

        div.search do
            form :action => redir, :method => 'get' do
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
                tr { th 'Date'      ; td @patch.date.strftime(DATEFORMAT) }
                tr { th 'Patch ID'; td @patch.altid }
                tr { th 'Download'  ; td { a @patch.filename, :href => R(Download, @patch.id, @patch.filename) } }
                if @logged_in
                    tr { th 'State' ; td do
                        tag! :select, :name => 'state_id' do
                            @states.each do |s|
                                #tag! :option, s.name, :value => s.id, :selected => true
                                if s.id == @patch.state_id
                                    tag! :option, s.name, :value => s.id, :selected =>nil 
                                else
                                    tag! :option, s.name, :value => s.id
                                end
                            end
                        end
                    end }
                    tr { th 'Branches' ; td do
                        @branches.each do |b|
                            if @patch.branches.find_by_id b.id
                                input b.name, :type => 'checkbox', :name => "branch[#{b.id}]", :value => @has_branches[b.id], :checked => true
                            else
                                input b.name, :type => 'checkbox', :name => "branch[#{b.id}]", :value => @has_branches[b.id]
                            end
                        end
                    end }
                else
                    tr { th 'State'     ; td @patch.state.name }
                    tr { th 'Branches'  ; td { @patch.branches.map { |b| capture { b.name }}.join(" ")} }
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
