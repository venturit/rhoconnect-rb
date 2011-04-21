require File.join(File.dirname(__FILE__), 'spec_helper')

describe Rhosync::EndpointHelpers do
  
  # Auth stub class
  class AuthTest; end
  class BrokenResource < ActiveRecord::Base
    include Rhosync::Resource
  end
  
  # Query stub class
  class Product < ActiveRecord::Base
    include Rhosync::Resource
    def self.rhosync_query(partition)
      [self.new]
    end
  end
  
  def setup_auth_test(success)
    AuthTest.stub!(:do_auth).and_return(success)
    AuthTest.should_receive(:do_auth).with(@creds)
    
    Rhosync.configure do |config|
      config.uri = "http://test.rhosync.com"
      config.token = "token"
      config.authenticate = lambda {|credentials|
        AuthTest.do_auth(credentials)
      }  
    end
  end
  
  before(:all) do
    @params = {'partition' => 'testuser', 'resource' => 'Product'}
    @creds = {'user' => 'john', 'pass' => 'secret'}
  end
  
  context "on Rails auth endpoint" do
    before(:each) do
      strio = mock("StringIO")
      strio.stub!(:read).and_return(JSON.generate(@creds))
      @env = mock("env")
      @env.stub!(:body).and_return(strio)
      @env.stub!(:content_type).and_return('application/json')
      Rack::Request.stub!(:new).and_return(@env)
    end
    
    it "should call configured authenticate block" do
      setup_auth_test(true)
      Rhosync::Authenticate.call(@env).should == [
        200, {'Content-Type' => 'text/plain'}, [""]
      ]
    end
    
    it "should call configured authenticate block with 401" do
      setup_auth_test(false)
      Rhosync::Authenticate.call(@env).should == [
        401, {'Content-Type' => 'text/plain'}, [""]
      ]
    end
    
    it "should return true if no authenticate block exists" do
      Rhosync.configure do |config|
        config.uri = "http://test.rhosync.com"
        config.token = "token" 
      end
      Rhosync.configuration.authenticate.should be_nil
      Rhosync::Authenticate.call(@env).should == [
        200, {'Content-Type' => 'text/plain'}, [""]
      ]
    end
  end
    
  context "on Create/Update/Query endpoints" do
    before(:each) do
      @strio = mock("StringIO")
      @env = mock("env")
      @env.stub!(:content_type).and_return('application/json')
    end
    
    it "should call query endpoint" do
      @strio.stub!(:read).and_return(
        {'partition' => 'testuser', 'resource' => 'Product'}.to_json
      )
      @env.stub!(:body).and_return(@strio)
      Rack::Request.stub!(:new).and_return(@env)
      code, content_type, body = Rhosync::Query.call(@env)
      code.should == 200
      content_type.should == { "Content-Type" => "application/json" }
      JSON.parse(body[0]).should == { '1' => Product.new.normalized_attributes }
    end
    
    it "should fail on missing Rhosync::Resource" do
      @strio.stub!(:read).and_return(
        {'partition' => 'testuser', 'resource' => 'Broken'}.to_json
      )
      @env.stub!(:body).and_return(@strio)
      Rack::Request.stub!(:new).and_return(@env)
      code, content_type, body = Rhosync::Query.call(@env)
      code.should == 404
      content_type.should == { "Content-Type" => "text/plain" }
      body[0].should == "Missing Rhosync::Resource Broken"
    end
    
    it "should fail on undefined rhosync_query method" do
      @strio.stub!(:read).and_return(
        {'partition' => 'testuser', 'resource' => 'BrokenResource'}.to_json
      )
      @env.stub!(:body).and_return(@strio)      
      Rack::Request.stub!(:new).and_return(@env)
      code, content_type, body = Rhosync::Query.call(@env)
      code.should == 500
      content_type.should == { "Content-Type" => "text/plain" }
      body[0].should == "Method `rhosync_query` is not defined on Rhosync::Resource BrokenResource" 
    end
    
    it "should call create endpoint" do
      params = {
        'resource' => 'Product',
        'partition' => 'app',
        'attributes' => {
          'name' => 'iphone',
          'brand' => 'apple'
        }
      }
      @strio.stub!(:read).and_return(params.to_json)
      product = mock("Product")
      product.stub!(:attributes=)
      product.stub!(:rhosync_new)
      product.stub!(:skip_rhosync_callbacks=)
      product.stub!(:save)
      product.stub!(:id).and_return(123)
      Product.stub!(:new).and_return(product)
      product.should_receive(:rhosync_new).with(params['partition'],params['attributes'])
      @env.stub!(:body).and_return(@strio)      
      Rack::Request.stub!(:new).and_return(@env)
      code, content_type, body = Rhosync::Create.call(@env)
      code.should == 200
      content_type.should == { "Content-Type" => "text/plain" }
      body.should == ['123']
    end
    
    it "should call update endpoint" do
      pending
      params = {
        'resource' => 'Product',
        'partition' => 'app',
        'attributes' => {
          'id' => '123',
          'name' => 'iphone',
          'brand' => 'apple'
        }
      }
      @strio.stub!(:read).and_return(params.to_json)
      product = mock("Product")
      product.stub!(:attributes=)
      product.stub!(:rhosync_update)
      product.stub!(:skip_rhosync_callbacks=)
      product.stub!(:save)
      product.stub!(:id).and_return(123)
      Product.stub!(:find).and_return(product)
      product.should_receive(:rhosync_update).with(params['partition'],params['attributes'])
      @env.stub!(:body).and_return(@strio)      
      Rack::Request.stub!(:new).and_return(@env)
      code, content_type, body = Rhosync::Update.call(@env)
      code.should == 200
      content_type.should == { "Content-Type" => "text/plain" }
      body.should == [""]
    end
  end
  
  context "on Sinatra endpoints" do    
    class EndpointTest
      include Sinatra::RhosyncHelpers
    end
  
    it "should register endpoints for authenticate and query" do
      strio = mock("StringIO")
      strio.stub!(:read).and_return(@creds.to_json)      
      req = mock("request")
      req.stub!(:body).and_return(strio)
      req.stub!(:env).and_return('CONTENT_TYPE' => 'application/json')
      Sinatra::RhosyncEndpoints.stub!(:request).and_return(req)
      Sinatra::RhosyncEndpoints.stub!(:params).and_return(@params)
      Rhosync::EndpointHelpers.stub!(:query)
      app = mock("app")
      app.stub!(:post).and_yield
      app.should_receive(:post).exactly(4).times
      app.should_receive(:include).with(Sinatra::RhosyncHelpers)
      Sinatra::RhosyncEndpoints.should_receive(:call_helper).exactly(4).times
      Sinatra::RhosyncEndpoints.registered(app)
    end
    
    it "should call helper for authenticate" do
      app = EndpointTest.new
      app.should_receive(:status).with(200)
      app.should_receive(:content_type).with('text/plain')
      app.call_helper(
        :authenticate, 'application/json', @creds.to_json
      ).should == ""
    end
    
    it "should call helper for query" do
      app = EndpointTest.new
      app.should_receive(:status).with(200)
      app.should_receive(:content_type).with('application/json')
      result = app.call_helper(
        :query, 'application/json', @params.to_json
      )
      JSON.parse(result).should == { '1' => Product.new.normalized_attributes }
    end
  end
end