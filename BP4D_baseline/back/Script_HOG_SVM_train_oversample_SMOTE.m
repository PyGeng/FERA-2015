function Script_HOG_SVM_train_oversample_SMOTE()

% Change to your downloaded location
addpath('C:\liblinear\matlab')

%% load shared definitions and AU data
shared_defs;

hyperparams.c = 10.^(-6:1:-4);
hyperparams.e = 10.^(-3);

hyperparams.under_ratio = [1];

% How many more samples to generate of positives
hyperparams.over_ratio = [0, 0.5, 1, 2, 3, 4];

hyperparams.validate_params = {'c', 'e', 'under_ratio', 'over_ratio'};

% Set the training function
svm_train = @svm_train_linear;
    
% Set the test function (the first output will be used for validation)
svm_test = @svm_test_linear;

pca_loc = '../pca_generation/generic_face_rigid.mat';

%%
for a=1:numel(aus)
    
    au = aus(a);
         
    % load the training and testing data for the current fold
    [train_samples, train_labels, valid_samples, valid_labels, raw_valid, PC, means, scaling] = Prepare_HOG_AU_data_generic(train_recs, devel_recs, au, BP4D_dir, hog_data_dir, pca_loc);

    train_samples = sparse(train_samples);
    valid_samples = sparse(valid_samples);

    %% Cross-validate here                
    [ best_params, ~ ] = validate_grid_search(svm_train, svm_test, false, train_samples, train_labels, valid_samples, valid_labels, hyperparams);

    model = svm_train(train_labels, train_samples, best_params);        

    [prediction, a, actual_vals] = predict(valid_labels, valid_samples, model);

    % Go from raw data to the prediction
    w = model.w(1:end-1)';
    b = model.w(end);

    svs = bsxfun(@times, PC, 1./scaling') * w;

    % Attempt own prediction
    preds_mine = bsxfun(@plus, raw_valid, -means) * svs + b;

    assert(norm(preds_mine - actual_vals) < 1e-8);
% 
%     name = sprintf('trained_sampling/AU_%d_static_under.dat', au);
% 
%     write_lin_svm(name, means, svs, b, model.Label(1), model.Label(2));

    name = sprintf('trained_sampling/AU_%d_static_over_SMOTE.mat', au);

    tp = sum(valid_labels == 1 & prediction == 1);
    fp = sum(valid_labels == 0 & prediction == 1);
    fn = sum(valid_labels == 1 & prediction == 0);
    tn = sum(valid_labels == 0 & prediction == 0);

    precision = tp/(tp+fp);
    recall = tp/(tp+fn);

    f1 = 2 * precision * recall / (precision + recall);    
    
    save(name, 'model', 'f1', 'precision', 'recall', 'best_params');
        
end

end

function [model] = svm_train_linear(train_labels, train_samples, hyper)
    comm = sprintf('-s 1 -B 1 -e %f -c %f -q', hyper.e, hyper.c);
    
    pos_count = sum(train_labels == 1);
    neg_count = sum(train_labels == 0);
            
    num_neighbors = 40;
    
    if(hyper.over_ratio > 0 && pos_count < neg_count)
                       
        inds_train = 1:size(train_labels,1);
        pos_samples = inds_train(train_labels == 1);
        
        % do not produce more pos than neg
        extra_num = min([round(pos_count * hyper.over_ratio), neg_count - pos_count]);
       
        train_labels_extra = ones(extra_num, 1);
        train_samples_extra = zeros(extra_num, size(train_samples, 2));
        
        pos_samples = full(train_samples(pos_samples,:));
        
        KDTreeMdl = KDTreeSearcher(pos_samples);
        
        extra_sampling = round(linspace(1, size(pos_samples,1), floor(extra_num / num_neighbors)));
        filled = 1;
        for i=extra_sampling
            
            % discard one as it will be self
            curr_sample = pos_samples(i,:);
            [idxMk, Dmk] = knnsearch(KDTreeMdl, curr_sample, 'k', 100);
            inds = randperm(100);
            inds = inds(1:num_neighbors);
            old_samples = pos_samples(idxMk(inds),:);
            
            weights = rand(num_neighbors, 1);
            
            new_samples = bsxfun(@times, old_samples, weights) + bsxfun(@times, curr_sample, 1 - weights);
            train_samples_extra(filled:filled+num_neighbors-1,:) = new_samples;
            filled = filled + num_neighbors;
        end
                
        train_labels = cat(1, train_labels, train_labels_extra(1:filled, :));
        train_samples = cat(1, train_samples, train_samples_extra(1:filled, :));        
        
    end
    
    pos_count = sum(train_labels == 1);
    neg_count = sum(train_labels == 0);
        
    if(pos_count * hyper.under_ratio < neg_count)
    
        % Remove two thirds of negative examples (to balance the training data a bit)
        inds_train = 1:size(train_labels,1);
        neg_samples = inds_train(train_labels == 0);
        reduced_inds = true(size(train_labels,1),1);
        to_rem = round(neg_count -  pos_count * hyper.under_ratio);
        neg_samples = neg_samples(round(linspace(1, size(neg_samples,2), to_rem)));
        
        reduced_inds(neg_samples) = false;

        train_labels = train_labels(reduced_inds, :);
        train_samples = train_samples(reduced_inds, :);
        
    end
        
    model = train(train_labels, train_samples, comm);
end

function [result, prediction] = svm_test_linear(test_labels, test_samples, model)

    w = model.w(1:end-1)';
    b = model.w(end);

    % Attempt own prediction
    prediction = test_samples * w + b;
    l1_inds = prediction > 0;
    l2_inds = prediction <= 0;
    prediction(l1_inds) = model.Label(1);
    prediction(l2_inds) = model.Label(2);
 
    tp = sum(test_labels == 1 & prediction == 1);
    fp = sum(test_labels == 0 & prediction == 1);
    fn = sum(test_labels == 1 & prediction == 0);
    tn = sum(test_labels == 0 & prediction == 0);

    precision = tp/(tp+fp);
    recall = tp/(tp+fn);

    f1 = 2 * precision * recall / (precision + recall);

    fprintf('F1:%.3f\n', f1);
    if(isnan(f1))
        f1 = 0;
    end
    result = f1;
end