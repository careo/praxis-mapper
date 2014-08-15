require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Praxis::Mapper::Resource do

  let(:parent_record) { ParentModel.new(id: 100, name: 'george sr') }
  let(:parent_records) { [ParentModel.new(id: 101, name: "georgia"),ParentModel.new(id: 102, name: 'georgina')] }
  let(:record) { SimpleModel.new(id: 103, name: 'george xvi') }
  let(:model) { SimpleModel}

  let(:identity_map) { Praxis::Mapper::IdentityMap.current }

  before do
    identity_map.add_records([parent_record]| parent_records)
    identity_map.add_records([record])
  end

  context 'configuration' do
    subject { SimpleResource }
    its(:model) { should == model }
    its(:member_name) { should == 'simple_resource' }
    its(:collection_name) { should == 'simple_resources' }
  end


  context 'retrieving resources' do

    context 'getting a single resource' do
      subject(:resource)  { SimpleResource.get(:name => 'george xvi') }

      it { should be_kind_of(SimpleResource) }

      its(:record) { should be record }
    end

    context 'getting multiple resources' do
      subject(:resource_collection) { SimpleResource.all(:name => ["george xvi"]) }

      it { should be_kind_of(Array) }

      it 'fetches the models and wraps them' do
        resource = resource_collection.first
        resource.should be_kind_of(SimpleResource)
        resource.record.should == record

      end
    end
  end

  context 'delegating to the underlying model' do

    subject { SimpleResource.new(record) }

    it 'does respond_to attributes in the model' do
      subject.should respond_to(:name)
    end

    it 'does not respond_to :id if the model does not have it' do
      resource = OtherResource.new(OtherModel.new(:name => "foo"))

      resource.should_not respond_to(:id)
    end


    it 'returns raw results for simple attributes' do
      record.should_receive(:name).and_call_original
      subject.name.should == "george xvi"
    end

    it 'wraps model objects in Resource instances' do
      record.should_receive(:parent).and_return(parent_record)

      parent = subject.parent

      parent.should be_kind_of(ParentResource)
      parent.name.should == "george sr"
      parent.record.should == parent_record
    end

    context "for serialized array associations" do
      let(:record) { YamlArrayModel.new(:id => 1)}

      subject { YamlArrayResource.new(record)}

      it 'wraps arrays of model objects in an array of resource instances' do
        record.should_receive(:parents).and_return(parent_records)

        parents = subject.parents
        parents.should have(parent_records.size).items
        parents.should be_kind_of(Array)

        parents.each { |parent| parent.should be_kind_of(ParentResource) }
        parents.collect { |parent| parent.record }.should =~ parent_records
      end
    end
  end

  context 'resource_delegate' do
    let(:other_name) { "foo" }
    let(:other_attribute) { "other value" }
    let(:other_record) { OtherModel.new(:name => other_name, :other_attribute => other_attribute)}
    let(:other_resource) { OtherResource.new(other_record) }

    let(:record) { SimpleModel.new(id: 105, name: "george xvi", other_name: other_name) }

    subject(:resource) { SimpleResource.new(record) }

    before do
      identity_map.add_records([other_record])
    end

    it 'delegates to the target' do
      resource.other_attribute.should == other_attribute
    end
  end


  context "memoized resource creation" do
    let(:other_name) { "foo" }
    let(:other_attribute) { "other value" }
    let(:other_record) { OtherModel.new(:name => other_name, :other_attribute => other_attribute)}
    let(:other_resource) { OtherResource.new(other_record) }
    let(:record) { SimpleModel.new(id: 105, name: "george xvi", other_name: other_name) }

    before do
      identity_map.add_records([other_record])
      identity_map.add_records([record])
    end

    subject(:resource) { SimpleResource.new(record) }

    it 'memoizes related resource creation' do
      resource.other_resource.should be(SimpleResource.new(record).other_resource)
    end

  end


  context ".wrap" do
    it 'memoizes resource creation' do
      SimpleResource.wrap(record).should be(SimpleResource.wrap(record))
    end

    it 'works with nil resources, returning an empty set' do
      wrapped_obj = SimpleResource.wrap(nil)
      wrapped_obj.should be_kind_of(Array)
      wrapped_obj.length.should be(0)
    end

    it 'works regardless of the resource class used' do
      SimpleResource.wrap(record).should be(OtherResource.wrap(record))
    end
  end

end
