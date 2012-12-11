# -*- encoding: UTF-8 -*-

require 'spec_helper'
require 'capybara/webkit'

module TestSessions
  Webkit = Capybara::Session.new(:reusable_webkit, TestApp)
end

Capybara::SpecHelper.run_specs TestSessions::Webkit, "webkit"

describe Capybara::Session do
  subject { Capybara::Session.new(:reusable_webkit, @app) }
  after { subject.reset! }

  context "slow javascript app" do
    before(:all) do
      @app = lambda do |env|
        body = <<-HTML
          <html><body>
            <form action="/next" id="submit_me"><input type="submit" value="Submit" /></form>
            <p id="change_me">Hello</p>

            <script type="text/javascript">
              var form = document.getElementById('submit_me');
              form.addEventListener("submit", function (event) {
                event.preventDefault();
                setTimeout(function () {
                  document.getElementById("change_me").innerHTML = 'Good' + 'bye';
                }, 500);
              });
            </script>
          </body></html>
        HTML
        [200,
          { 'Content-Type' => 'text/html', 'Content-Length' => body.length.to_s },
          [body]]
      end
    end

    before do
      @default_wait_time = Capybara.default_wait_time
      Capybara.default_wait_time = 1
    end

    after { Capybara.default_wait_time = @default_wait_time }

    it "waits for a request to load" do
      subject.visit("/")
      subject.find_button("Submit").click
      subject.should have_content("Goodbye");
    end
  end

  context "simple app" do
    before(:all) do
      @app = lambda do |env|
        body = <<-HTML
          <html><body>
            <strong>Hello</strong>
            <span>UTF8文字列</span>
            <input type="button" value="ボタン" />
          </body></html>
        HTML
        [200,
          { 'Content-Type' => 'text/html; charset=UTF-8', 'Content-Length' => body.length.to_s },
          [body]]
      end
    end

    before do
      subject.visit("/")
    end

    it "inspects nodes" do
      subject.all(:xpath, "//strong").first.inspect.should include("strong")
    end

    it "can read utf8 string" do
      utf8str = subject.all(:xpath, "//span").first.text
      utf8str.should eq('UTF8文字列')
    end

    it "can click utf8 string" do
      subject.click_button('ボタン')
    end
  end

  context "response headers with status code" do
    before(:all) do
      @app = lambda do |env|
        params = ::Rack::Utils.parse_query(env['QUERY_STRING'])
        if params["img"] == "true"
          body = 'not found'
          return [404, { 'Content-Type' => 'image/gif', 'Content-Length' => body.length.to_s }, [body]]
        end
        body = <<-HTML
          <html>
            <body>
              <img src="?img=true">
            </body>
          </html>
        HTML
        [200,
          { 'Content-Type' => 'text/html', 'Content-Length' => body.length.to_s, 'X-Capybara' => 'WebKit'},
          [body]]
      end
    end

    it "should get status code" do
      subject.visit '/'
      subject.status_code.should == 200
    end

    it "should reset status code" do
      subject.visit '/'
      subject.status_code.should == 200
      subject.reset!
      subject.status_code.should == 0
    end

    it "should get response headers" do
      subject.visit '/'
      subject.response_headers['X-Capybara'].should == 'WebKit'
    end

    it "should reset response headers" do
      subject.visit '/'
      subject.response_headers['X-Capybara'].should == 'WebKit'
      subject.reset!
      subject.response_headers['X-Capybara'].should == nil
    end
  end

  context "slow iframe app" do
    before do
      @app = Class.new(ExampleApp) do
        get '/' do
          <<-HTML
          <html>
          <head>
          <script>
            function hang() {
              xhr = new XMLHttpRequest();
              xhr.onreadystatechange = function() {
                if(xhr.readyState == 4){
                  document.getElementById('p').innerText = 'finished'
                }
              }
              xhr.open('GET', '/slow', true);
              xhr.send();
              document.getElementById("f").src = '/iframe';
              return false;
            }
          </script>
          </head>
          <body>
            <a href="#" onclick="hang()">Click Me!</a>
            <iframe src="about:blank" id="f"></iframe>
            <p id="p"></p>
          </body>
          </html>
          HTML
        end

        get '/slow' do
          sleep 1
          status 204
        end

        get '/iframe' do
          status 204
        end
      end
    end

    it "should not hang the server" do
      subject.visit("/")
      subject.click_link('Click Me!')
      Capybara.using_wait_time(5) do
        subject.should have_content("finished")
      end
    end
  end

  context "session app" do
    before do
      @app = Class.new(ExampleApp) do
        enable :sessions
        get '/' do
          <<-HTML
          <html>
          <body>
            <form method="post" action="/sign_in">
              <input type="text" name="username">
              <input type="password" name="password">
              <input type="submit" value="Submit">
            </form>
          </body>
          </html>
          HTML
        end

        post '/sign_in' do
          session[:username] = params[:username]
          session[:password] = params[:password]
          redirect '/'
        end

        get '/other' do
          <<-HTML
          <html>
          <body>
            <p>Welcome, #{session[:username]}.</p>
          </body>
          </html>
          HTML
        end
      end
    end

    it "should not start queued commands more than once" do
      subject.visit('/')
      subject.fill_in('username', with: 'admin')
      subject.fill_in('password', with: 'temp4now')
      subject.click_button('Submit')
      subject.visit('/other')
      subject.should have_content('admin')
    end
  end

  context "iframe app" do
    before(:all) do
      @app = Class.new(ExampleApp) do
        get '/' do
          <<-HTML
            <!DOCTYPE html>
            <html>
            <body>
              <h1>Main Frame</h1>
              <iframe src="/a" name="a_frame" width="500" height="500"></iframe>
            </body>
            </html>
          HTML
        end

        get '/a' do
          <<-HTML
            <!DOCTYPE html>
            <html>
            <body>
              <h1>Page A</h1>
              <iframe src="/b" name="b_frame" width="500" height="500"></iframe>
            </body>
            </html>
          HTML
        end

        get '/b' do
          <<-HTML
            <!DOCTYPE html>
            <html>
            <body>
              <h1>Page B</h1>
              <form action="/c" method="post">
              <input id="button" name="commit" type="submit" value="B Button">
              </form>
            </body>
            </html>
          HTML
        end

        post '/c' do
          <<-HTML
            <!DOCTYPE html>
            <html>
            <body>
              <h1>Page C</h1>
            </body>
            </html>
          HTML
        end
      end
    end

    it 'supports clicking an element offset from the viewport origin' do
      subject.visit '/'

      subject.within_frame 'a_frame' do
        subject.within_frame 'b_frame' do
          subject.click_button 'B Button'
          subject.should have_content('Page C')
        end
      end
    end
  end

  context 'click tests' do
    before(:all) do
      @app = Class.new(ExampleApp) do
        get '/' do
          <<-HTML
            <!DOCTYPE html>
            <html>
            <head>
            <style>
              body {
                width: 800px;
                margin: 0;
              }
              .target {
                width: 200px;
                height: 200px;
                float: left;
                margin: 100px;
              }
            </style>
            <body>
              <div id="one" class="target"></div>
              <div id="two" class="target"></div>
              <script type="text/javascript">
                var targets = document.getElementsByClassName('target');
                for (var i = 0; i < targets.length; i++) {
                  var target = targets[i];
                  target.onclick = function(event) {
                    this.setAttribute('data-click-x', event.clientX);
                    this.setAttribute('data-click-y', event.clientY);
                  };
                }
              </script>
            </body>
            </html>
          HTML
        end
      end
    end

    it 'clicks in the center of an element' do
      subject.visit('/')
      subject.find(:css, '#one').click
      subject.find(:css, '#one')['data-click-x'].should == '199'
      subject.find(:css, '#one')['data-click-y'].should == '199'
    end

    it 'clicks in the center of the viewable area of an element' do
      subject.visit('/')
      subject.driver.resize_window(200, 200)
      subject.find(:css, '#one').click
      subject.find(:css, '#one')['data-click-x'].should == '149'
      subject.find(:css, '#one')['data-click-y'].should == '99'
    end

    it 'scrolls an element into view when clicked' do
      subject.visit('/')
      subject.driver.resize_window(200, 200)
      subject.find(:css, '#two').click
      subject.find(:css, '#two')['data-click-x'].should_not be_nil
      subject.find(:css, '#two')['data-click-y'].should_not be_nil
    end
  end
end
