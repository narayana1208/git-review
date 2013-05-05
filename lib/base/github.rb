require 'net/http'
require 'net/https'
# Used to handle json data
require 'yajl'
# Required to hide password
require 'io/console'
# Required by yajl for decoding
require 'stringio'
# Used to retrieve hostname
require 'socket'
require 'singleton'

# module GitReview

  class Github

    include Singleton

    attr_reader :github

    def initialize
      #configure_github_access
    end

    # setup connection with Github via OAuth
    def configure_github_access
      if Settings.instance.oauth_token
        @github = Octokit::Client.new(
          :login          => Settings.instance.username,
          :oauth_token    => Settings.instance.oauth_token,
          :auto_traversal => true
        )
        @github.login
      else
        configure_oauth
        configure_github_access
      end
    end

    # list pull requests for a repository
    def pull_requests(repo, state='open')
      args = stringify(repo, state)
      @github.pull_requests(*args).collect { |request|
        Request.new.update_from_mash(request)
      }
    end

    # get a pull request
    def pull_request(repo, number)
      args = stringify(repo, number)
      Request.new.update_from_mash(@github.pull_request(*args))
    end

    # get all comments attached to an issue
    def issue_comments(repo, number)
      args = stringify(repo, number)
      @github.issue_comments(*args).collect { |comment|
        Comment.new.update_from_mash(comment)
      }
    end

    # get a single comment attached to an issue
    def issue_comment(repo, number)
      args = stringify(repo, number)
      Comment.new.update_from_mash(@github.issue_comment(*args))
    end

    # list comments on a pull request
    def pull_request_comments(repo, number)
      args = stringify(repo, number)
      @github.pull_request_comments(*args) { |comment|
        Comment.new.update_from_mash(comment)
      }
    end
    alias_method :pull_comments, :pull_request_comments
    alias_method :review_comments, :pull_request_comments

    # list commits on a pull request
    def pull_request_commits(repo, number)
      args = stringify(repo, number)
      @github.pull_request_commits(*args) { |commit|
        Commit.new.update_from_mash(commit)
      }
    end
    alias_method :pull_commits, :pull_request_commits

    # close an issue
    def close_issue(repo, number)
      args = stringify(repo, number)
      @github.close_issue(*args)
    end

    # add a comment to an issue
    def add_comment(repo, number, comment)
      args = stringify(repo, number, comment)
      @github.add_comment(*args)
    end

    # create a pull request
    def create_pull_request(repo, base, head, title, body)
      args = stringify(repo, base, head, title, body)
      @github.create_pull_request(*args)
    end

  private

    def configure_oauth
      begin
        prepare_username_and_password
        prepare_description
        authorize
      rescue Errors::AuthenticationError => e
        warn e.message
      rescue Errors::UnprocessableState => e
        warn e.message
        exit 1
      end
    end

    def prepare_username_and_password
      puts "Requesting a OAuth token for git-review."
      puts "This procedure will grant access to your public and private "\
      "repositories."
      puts "You can revoke this authorization by visiting the following page: "\
      "https://github.com/settings/applications"
      print "Please enter your GitHub's username: "
      @username = STDIN.gets.chomp
      print "Please enter your GitHub's password (it won't be stored anywhere): "
      @password = STDIN.noecho(&:gets).chomp
      print "\n"
    end

    def prepare_description(chosen_description=nil)
      if chosen_description
        @description = chosen_description
      else
        @description = "git-review - #{Socket.gethostname}"
        puts "Please enter a description to associate to this token, it will "\
        "make easier to find it inside of GitHub's application page."
        puts "Press enter to accept the proposed description"
        print "Description [#{@description}]:"
        user_description = STDIN.gets.chomp
        @description = user_description.empty? ? @description : user_description
      end
    end

    def authorize
      uri = URI('https://api.github.com/authorizations')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      req = Net::HTTP::Post.new(uri.request_uri)
      req.basic_auth(@username, @password)
      req.body = Yajl::Encoder.encode(
        {
          'scopes' => ['repo'],
          'note'   => @description
        }
      )
      response = http.request(req)
      if response.code == '201'
        parser_response = Yajl::Parser.parse(response.body)
        save_oauth_token(parser_response['token'])
      elsif response.code == '401'
        raise Errors::AuthenticationError
      else
        raise Errors::UnprocessableState(response.body)
      end
    end

    def save_oauth_token(token)
      settings = Settings.instance
      settings.oauth_token = token
      settings.username = @username
      settings.save!
      puts "OAuth token successfully created.\n"
    end

    # stringify all arguments depending on how to_s is defined for each
    def stringify(*args)
      args.map(&:to_s)
    end

  end

# end
