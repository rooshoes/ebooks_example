# ebooks_example

As requested, this is the [twitter_ebooks](https://github.com/mispy/twitter_ebooks) app which I use to run most of my own bots. It tweets one guaranteed tweet every 24h, always responds to interactions, and has some small unprompted interaction probability based on keyword matching.

## Usage

```bash
git clone https://github.com/rooshoes/ebooks_example.git
cd ebooks_example
bundle install
bundle exec ebooks archive username corpus/username.json
bundle exec ebooks consume corpus/username.json
```

Populate bots.rb with your auth details, the bot username and model name, then:

`bundle exec ebooks start`

Also runs as a Heroku app! See the [twitter_ebooks](https://github.com/mispy/twitter_ebooks) README for more information.
