require 'twitter_ebooks'

# Information about a particular Twitter user we know
class UserInfo
  attr_reader :username

  # @return [Integer] how many times we can pester this user unprompted
  attr_accessor :pesters_left

  # @param username [String]
  def initialize(username)
    @username = username
    @pesters_left = 1
  end
end

class CloneBot < Ebooks::Bot
  attr_accessor :owner, :model, :model_path, :schedule

  def configure
    # Configuration for all CloneBots
    self.owner = @config['twitter']['owner']
    self.blacklist = Array(@config['twitter']['blacklist'])
    self.delay_range = 1..6
    @userinfo = {}
  end

  def top100; @top100 ||= model.keywords.take(100); end
  def top20;  @top20  ||= model.keywords.take(20); end

  def on_startup
    load_model!

    def scheduler.on_error(job, error)
      msg = "Scheduler intercepted error in job #{job.id}: #{error.message}"
      alert_owner(msg)
    end
    set_schedule( @config['twitter']['frequency'] || '25m' )
  end

  def on_message(dm)
    delay do
      reply(dm, model.make_response(dm.text))
    end
  end

  def on_mention(tweet)
    # Become more inclined to pester a user when they talk to us
    userinfo(tweet.user.screen_name).pesters_left += 1

    delay do
      reply(tweet, model.make_response(meta(tweet).mentionless, meta(tweet).limit))
    end
  end

  def on_timeline(tweet)
    return if tweet.retweeted_status?
    return unless can_pester?(tweet.user.screen_name)

    tokens = Ebooks::NLP.tokenize(tweet.text)

    interesting = tokens.find { |t| top100.include?(t.downcase) }
    very_interesting = tokens.find_all { |t| top20.include?(t.downcase) }.length > 2

    delay do
      if very_interesting
        favorite(tweet) if rand < 0.5
        retweet(tweet) if rand < 0.1
        if rand < 0.01
          userinfo(tweet.user.screen_name).pesters_left -= 1
          reply(tweet, model.make_response(meta(tweet).mentionless, meta(tweet).limit))
        end
      elsif interesting
        favorite(tweet) if rand < 0.05
        if rand < 0.001
          userinfo(tweet.user.screen_name).pesters_left -= 1
          reply(tweet, model.make_response(meta(tweet).mentionless, meta(tweet).limit))
        end
      end
    end
  end

  # Find information we've collected about a user
  # @param username [String]
  # @return [Ebooks::UserInfo]
  def userinfo(username)
    @userinfo[username] ||= UserInfo.new(username)
  end

  # Check if we're allowed to send unprompted tweets to a user
  # @param username [String]
  # @return [Boolean]
  def can_pester?(username)
    userinfo(username).pesters_left > 0
  end

  # Only follow our owner or people who are following our owner
  # @param user [Twitter::User] 
  def can_follow?(username)
    @config['twitter']['follows?'] == 'all' || @owner.nil? || username == @owner || twitter.friendship?(username, @owner)
  end

  def favorite(tweet)
    if can_follow?(tweet.user.screen_name)
      super(tweet)
    else
      log "Unfollowing @#{tweet.user.screen_name}"
      twitter.unfollow(tweet.user.screen_name)
    end
  end

  def on_follow(user)
    if can_follow?(user.screen_name)
      follow(user.screen_name)
    else
      log "Not following @#{user.screen_name}"
    end
  end

  def alert_owner(*args)
    msg = args.map(&:to_s).join(' ')
    log "Alert:", msg
    twitter.create_direct_message(@owner, msg) unless @owner.nil?
  end

  def last_tweet
    twitter.user_timeline(username, count: 1, exclude_replies: true)[0]
  end

  def block_user(users)
    return if users.empty?
    begin
      twitter.block(users)
    rescue Twitter::Error => e
      alert_owner "Error: #{e.message}"
    else
      self.blacklist.push(users)
      alert_owner "Blocked user(s) #{users.join(', ')}."
    end
  end

  def delete_tweet(tweets)
    return if tweets.empty?
    begin
      twitter.destroy_tweet(tweets)
    rescue Twitter::Error => e
      alert_owner "Error: #{e.message}"
    else
      alert_owner "Deleted tweet(s) #{tweets.join(', ')}."
    end
  end

  def set_schedule(interval)
    @schedule.unschedule if @schedule
    @schedule = scheduler.every interval.to_s, :job => true do
      # Every interval [String], post a single tweet
      tweet(model.make_statement)
    end
    alert_owner "Now tweeting every #{@schedule.original}."
  end

  private
  def load_model!
    return if @model

    @model_path ||= "model/#{@config['model']}.model"

    log "Loading model #{model_path}"
    @model = Ebooks::Model.load(model_path)
  end
end

